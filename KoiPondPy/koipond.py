"""Koi Pond: a Python / pygame port of KoiPondJS that runs in Pydroid 3.

Original: https://github.com/markspan/KoiPondJS (p5.js + p5.scribble).

What it shows
-------------
A school of translucent, hand-drawn looking "koi" that swim around a dark
pond. Two independent models are combined per fish:

* Steering (Craig Reynolds' boids): separation, alignment and cohesion
  forces decide where each fish goes. See https://www.red3d.com/cwr/ and
  https://natureofcode.com.
* Body (a "flagellum"): a chain of nodes driven by an oscillating neck
  muscle. Every following node is pulled behind the one in front of it,
  which produces the undulating swimming motion. The faster a fish swims,
  the faster its muscle beats.

Every body segment is drawn as a filled translucent ellipse plus a jittery
"scribble" outline that is re-randomised each frame, mimicking the
p5.scribble look of the original.

Running on Android (Pydroid 3)
------------------------------
1. Install pygame: Pydroid menu -> Pip -> search "pygame" -> Install
   (Pydroid ships a prebuilt Android wheel).
2. Open this file and press the yellow Run button. Pydroid detects the
   pygame import and starts it full screen in its SDL runner.

Controls
--------
* Tap / click: drop a new koi at that spot (up to ``MAX_KOI``).
* Back button, Escape or closing the window: quit.

The script also runs unchanged on a desktop with ``pip install pygame``.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass

import pygame
import pygame.gfxdraw
from pygame.math import Vector2

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PondConfig:
    """All tunable constants in one place.

    Distances and speeds are expressed in "reference pixels" and multiplied
    by a per-screen scale factor (see :meth:`Pond.scale`), so the pond looks
    the same on a low-density desktop window and a high-density phone.
    """

    # Scene
    initial_koi: int = 15
    max_koi: int = 40
    fps: int = 60
    background: tuple[int, int, int] = (55, 55, 55)
    # Short screen side (in pixels) at which ``scale`` equals 1.
    reference_short_side: float = 400.0

    # Boid steering (values from the original sketch)
    separation_distance: float = 40.0
    alignment_distance: float = 40.0
    cohesion_distance: float = 50.0
    separation_weight: float = 0.01
    alignment_weight: float = 0.03
    cohesion_weight: float = 0.01
    max_force: float = 0.3
    min_speed: float = 1.0
    max_speed: float = 2.0

    # Body
    min_segment_factor: float = 0.75  # fsize = random(min, max) * scale
    max_segment_factor: float = 1.5
    min_nodes: float = 2.0  # num_nodes = random(min, max) * fsize
    max_nodes: float = 6.0
    muscle_range_deg: float = 6.0
    muscle_rate_per_speed: float = 0.06  # radians of muscle phase per unit speed

    # Look
    body_alpha: int = 20  # fill alpha, as in the original
    outline_rgba: tuple[int, int, int, int] = (250, 250, 250, 100)
    scribble_roughness: float = 1.2
    scribble_passes: int = 2


CONFIG = PondConfig()


# ---------------------------------------------------------------------------
# Small vector helpers
# ---------------------------------------------------------------------------


def limit(vector: Vector2, max_length: float) -> Vector2:
    """Clamp ``vector`` in place to ``max_length`` and return it.

    Equivalent to p5's ``Vector.limit``. Implemented by hand because
    ``Vector2.clamp_magnitude`` is missing in older pygame builds.
    """
    if vector.length_squared() > max_length * max_length:
        vector.scale_to_length(max_length)
    return vector


def set_length(vector: Vector2, length: float) -> Vector2:
    """Scale ``vector`` in place to ``length`` (no-op for the zero vector)."""
    if vector.length_squared() > 0.0:
        vector.scale_to_length(length)
    return vector


# ---------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------


def ellipse_points(
    center: Vector2,
    radius_x: float,
    radius_y: float,
    rotation: float,
    jitter: float = 0.0,
) -> list[tuple[int, int]]:
    """Return polygon vertices approximating a rotated ellipse.

    Args:
        center: Ellipse centre in screen coordinates.
        radius_x: Semi-axis along the ellipse's own x direction.
        radius_y: Semi-axis along the ellipse's own y direction.
        rotation: Rotation of the ellipse in radians.
        jitter: Maximum random offset, in pixels, applied to each vertex.
            A non-zero value produces the hand-drawn scribble look.
    """
    # More vertices for bigger ellipses, but keep small ones cheap.
    segments = max(8, min(36, int((radius_x + radius_y) * 0.8)))
    cos_r, sin_r = math.cos(rotation), math.sin(rotation)
    points = []
    for i in range(segments):
        t = 2.0 * math.pi * i / segments
        ex = radius_x * math.cos(t)
        ey = radius_y * math.sin(t)
        if jitter:
            ex += random.uniform(-jitter, jitter)
            ey += random.uniform(-jitter, jitter)
        points.append(
            (
                int(center.x + ex * cos_r - ey * sin_r),
                int(center.y + ex * sin_r + ey * cos_r),
            )
        )
    return points


def draw_sketchy_ellipse(
    surface: pygame.Surface,
    center: Vector2,
    fill_size: tuple[float, float],
    scribble_size: tuple[float, float],
    rotation: float,
    fill_rgba: tuple[int, int, int, int],
    config: PondConfig = CONFIG,
) -> None:
    """Draw one body segment: translucent fill, outline and scribbles.

    ``fill_size`` and ``scribble_size`` are full diameters (width, height),
    matching p5's ``ellipse`` / ``scribbleEllipse`` arguments.
    """
    rx, ry = fill_size[0] / 2.0, fill_size[1] / 2.0
    if rx < 1.0 or ry < 1.0:
        return  # Too small to see; gfxdraw also dislikes degenerate polygons.

    outline = ellipse_points(center, rx, ry, rotation)
    # gfxdraw blends RGBA colours onto the target, unlike pygame.draw.
    pygame.gfxdraw.filled_polygon(surface, outline, fill_rgba)
    pygame.gfxdraw.aapolygon(surface, outline, config.outline_rgba)

    srx, sry = scribble_size[0] / 2.0, scribble_size[1] / 2.0
    for _ in range(config.scribble_passes):
        jittered = ellipse_points(
            center, srx, sry, rotation, jitter=config.scribble_roughness
        )
        pygame.gfxdraw.aapolygon(surface, jittered, config.outline_rgba)


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------


class Flagellum:
    """An undulating chain of nodes forming a fish body.

    The body is simulated in a local frame where the head sits near the
    origin and the tail trails along the positive x axis. :class:`Koi`
    rotates and translates this frame into the pond when drawing.
    """

    #: Fixed heading of the head in the local frame (degrees), as in the original.
    HEAD_ANGLE_DEG = 180.0

    def __init__(self, scale: float, config: PondConfig = CONFIG) -> None:
        self.config = config
        self.fsize = random.uniform(
            config.min_segment_factor, config.max_segment_factor
        ) * scale
        # At least three nodes: head, neck and one spine node.
        self.num_nodes = max(
            3, int(random.uniform(config.min_nodes, config.max_nodes) * self.fsize)
        )
        self.segment_length = 3.0 * self.fsize
        self.muscle_phase = 0.0
        self.muscle_rate = 0.0
        self.nodes = [Vector2() for _ in range(self.num_nodes)]

    @property
    def length(self) -> float:
        """Approximate body length, used for wrap-around margins."""
        return 2.0 * self.num_nodes * self.fsize

    def move(self) -> None:
        """Advance the muscle and drag the spine behind the head."""
        theta = math.radians(self.HEAD_ANGLE_DEG)
        head = self.nodes[0]
        head.update(math.cos(theta), math.sin(theta))

        # Neck: oscillates around the head direction.
        self.muscle_phase += self.muscle_rate
        neck_angle = theta + math.radians(
            self.config.muscle_range_deg * math.sin(self.muscle_phase)
        )
        self.nodes[1].update(
            head.x - self.segment_length * math.cos(neck_angle),
            head.y - self.segment_length * math.sin(neck_angle),
        )

        # Spine: each node keeps a fixed distance from its predecessor, in the
        # direction it had relative to the node two places ahead.
        for n in range(2, self.num_nodes):
            direction = self.nodes[n] - self.nodes[n - 2]
            if direction.length_squared() == 0.0:
                direction = Vector2(1.0, 0.0)  # Avoid division by zero.
            direction.scale_to_length(self.segment_length)
            self.nodes[n] = self.nodes[n - 1] + direction

    def draw(
        self,
        surface: pygame.Surface,
        origin: Vector2,
        rotation: float,
        fill_rgba: tuple[int, int, int, int],
    ) -> None:
        """Draw the body with its local frame placed at ``origin``/``rotation``."""

        def to_world(local: Vector2) -> Vector2:
            return origin + local.rotate_rad(rotation)

        size = self.fsize * self.num_nodes

        # Head: one larger ellipse aligned with the neck.
        neck_dir = self.nodes[1] - self.nodes[0]
        head_angle = math.atan2(neck_dir.y, neck_dir.x) + rotation
        draw_sketchy_ellipse(
            surface,
            to_world(self.nodes[0]),
            fill_size=(1.2 * size, 1.0 * size),
            scribble_size=(1.22 * size, 1.02 * size),
            rotation=head_angle,
            fill_rgba=fill_rgba,
            config=self.config,
        )

        # Body: circles shrinking towards the tail.
        for n in range(1, self.num_nodes):
            diameter = 0.5 * self.fsize * (self.num_nodes - n)
            draw_sketchy_ellipse(
                surface,
                to_world(self.nodes[n]),
                fill_size=(diameter, diameter),
                scribble_size=(diameter, diameter),
                rotation=0.0,
                fill_rgba=fill_rgba,
                config=self.config,
            )


class Koi:
    """A boid that steers with the flock and swims with a :class:`Flagellum`."""

    def __init__(self, position: Vector2, scale: float, config: PondConfig = CONFIG):
        self.config = config
        self.scale = scale
        self.body = Flagellum(scale, config)
        self.position = Vector2(position)
        self.velocity = Vector2(1.0, 0.0).rotate(random.uniform(0.0, 360.0))
        self.acceleration = Vector2()
        self.max_speed = random.uniform(config.min_speed, config.max_speed) * scale
        self.max_force = config.max_force * scale
        self.color = (
            random.randrange(256),
            random.randrange(256),
            random.randrange(256),
            config.body_alpha,
        )

    # -- steering -----------------------------------------------------------

    def _seek(self, target: Vector2) -> Vector2:
        """Steering force towards ``target`` (desired minus velocity)."""
        desired = set_length(target - self.position, self.max_speed)
        return limit(desired - self.velocity, self.max_force)

    def _steer_towards(self, heading: Vector2) -> Vector2:
        """Reynolds steering: full-speed ``heading`` minus current velocity."""
        desired = set_length(Vector2(heading), self.max_speed)
        return limit(desired - self.velocity, self.max_force)

    def flock(self, school: list[Koi]) -> None:
        """Accumulate separation, alignment and cohesion into acceleration."""
        cfg = self.config
        sep_dist = cfg.separation_distance * self.scale
        ali_dist = cfg.alignment_distance * self.scale
        coh_dist = cfg.cohesion_distance * self.scale

        away, heading_sum, center_sum = Vector2(), Vector2(), Vector2()
        n_sep = n_ali = n_coh = 0

        # One pass over the school collects all three neighbourhoods.
        for other in school:
            if other is self:
                continue
            offset = self.position - other.position
            d = offset.length()
            if d == 0.0:
                continue
            if d < sep_dist:
                away += offset / (d * d)  # Normalised, then weighted by 1/d.
                n_sep += 1
            if d < ali_dist:
                heading_sum += other.velocity
                n_ali += 1
            if d < coh_dist:
                center_sum += other.position
                n_coh += 1

        if n_sep and away.length_squared() > 0.0:
            self.acceleration += self._steer_towards(away) * cfg.separation_weight
        if n_ali and heading_sum.length_squared() > 0.0:
            self.acceleration += (
                self._steer_towards(heading_sum) * cfg.alignment_weight
            )
        if n_coh:
            self.acceleration += self._seek(center_sum / n_coh) * cfg.cohesion_weight

    # -- motion -------------------------------------------------------------

    def update(self) -> None:
        """Integrate motion and let the body swim at a speed-dependent beat."""
        self.velocity += self.acceleration
        limit(self.velocity, self.max_speed)
        self.position += self.velocity
        self.acceleration.update(0.0, 0.0)

        speed = self.velocity.length() / self.scale  # In reference pixels.
        self.body.muscle_rate = speed * self.config.muscle_rate_per_speed
        self.body.move()

    def wrap(self, width: int, height: int) -> None:
        """Re-enter on the opposite side once fully off screen."""
        margin = self.body.length
        if self.position.x < -margin:
            self.position.x = width + margin
        elif self.position.x > width + margin:
            self.position.x = -margin
        if self.position.y < -margin:
            self.position.y = height + margin
        elif self.position.y > height + margin:
            self.position.y = -margin

    def draw(self, surface: pygame.Surface) -> None:
        """Draw the body facing along the velocity (local tail is +x)."""
        rotation = math.atan2(self.velocity.y, self.velocity.x) + math.pi
        self.body.draw(surface, self.position, rotation, self.color)


class Pond:
    """Owns the window, the school of koi and the main loop."""

    def __init__(self, config: PondConfig = CONFIG) -> None:
        self.config = config
        # Only video is needed; skipping audio avoids mixer issues on Android.
        pygame.display.init()
        pygame.display.set_caption("Koi Pond")
        # (0, 0) + FULLSCREEN uses the native resolution; on Android this is
        # the whole screen, on a desktop it fills the monitor.
        self.screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        self.clock = pygame.time.Clock()
        self.school: list[Koi] = []
        for _ in range(config.initial_koi):
            self.spawn(self.random_position())

    @property
    def scale(self) -> float:
        """Screen-density factor applied to all sizes, distances and speeds."""
        width, height = self.screen.get_size()
        return min(width, height) / self.config.reference_short_side

    def random_position(self) -> Vector2:
        width, height = self.screen.get_size()
        return Vector2(random.uniform(0, width), random.uniform(0, height))

    def spawn(self, position: Vector2) -> None:
        """Add a koi at ``position`` unless the pond is full."""
        if len(self.school) < self.config.max_koi:
            self.school.append(Koi(position, self.scale, self.config))

    def handle_events(self) -> bool:
        """Process input. Returns ``False`` when the app should quit."""
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return False
            if event.type == pygame.KEYDOWN and event.key in (
                pygame.K_ESCAPE,
                getattr(pygame, "K_AC_BACK", pygame.K_ESCAPE),  # Android back.
            ):
                return False
            if event.type == pygame.MOUSEBUTTONDOWN:
                # Touches are delivered as mouse events on Android.
                self.spawn(Vector2(event.pos))
        return True

    def step(self) -> None:
        """Advance the simulation by one frame."""
        width, height = self.screen.get_size()
        for koi in self.school:
            koi.flock(self.school)
        for koi in self.school:
            koi.update()
            koi.wrap(width, height)

    def render(self) -> None:
        self.screen.fill(self.config.background)
        for koi in self.school:
            koi.draw(self.screen)
        pygame.display.flip()

    def run(self, max_frames: int | None = None) -> None:
        """Run the main loop; ``max_frames`` is for automated testing."""
        frame = 0
        try:
            while self.handle_events():
                self.step()
                self.render()
                self.clock.tick(self.config.fps)
                frame += 1
                if max_frames is not None and frame >= max_frames:
                    break
        finally:
            pygame.quit()


def main() -> None:
    Pond().run()


if __name__ == "__main__":
    main()
