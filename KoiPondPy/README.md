# KoiPondPy

A Python / pygame port of [KoiPondJS](https://github.com/markspan/KoiPondJS) that runs on Android in **Pydroid 3** (and on any desktop with pygame).

Translucent, hand-drawn looking koi swim around the pond. Steering uses Craig Reynolds' boids rules (separation, alignment, cohesion). Each body is a chain of nodes pulled along by an oscillating neck muscle, and the muscle beats faster when the fish swims faster.

## Run in Pydroid 3

1. Copy `koipond.py` to your phone.
2. In Pydroid: menu, **Pip**, search `pygame`, **Install**.
3. Open `koipond.py` and press **Run**. It starts full screen.

Tap to drop in a new koi. Press Back to quit.

## Run on a desktop

```bash
pip install pygame
```

```bash
python koipond.py
```

Press Escape to quit.

## Tuning

You can change every constant (fish count, flocking weights, colours, scribble roughness and so on) in the `PondConfig` dataclass at the top of `koipond.py`. Sizes, distances and speeds scale with the screen's short side, so phones and desktops look alike.

## Differences from the JavaScript version

- The pond fills the whole screen instead of the top quarter of the browser window, which suits a phone.
- Flocking forces are computed for all fish before any of them move, so the simulation does not depend on update order.
- The head ellipse is drawn aligned with the neck in proper world coordinates (the original rotated the canvas around the fish origin).
- Tapping adds a fish.
