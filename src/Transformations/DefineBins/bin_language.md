# The bin-definition language

`DefineBins` assigns events to **bins** using a small, readable
event-selection language. It replaces the ERPLAB EVENTLIST + BINLISTER step:
instead of a bin-descriptor file, you write one short statement per bin.

A script has two kinds of statement:

- **`bin` statements** — one per bin. Each is a **predicate over the events**
  in the recording; every event for which the predicate is true becomes a
  time-locked point (t = 0) for that bin.
- **one optional `epoch` statement** — the time window to cut around each
  matched event. It is written **once** and applies to **all** bins (every bin
  shares the same epoch window). With an `epoch` statement, `DefineBins`
  returns a segmented (`channels × time × trials`) dataset ready to plot and
  average; without it, the data stays continuous and only the bin tags are
  added.

- An event may belong to **several bins** at once.
- Events are considered in **latency order**.
- The result is written to `EEG.event(i).bini` (the bins each event is in) and
  `EEG.bindesc` (one record per bin: label, the compiled plan, matched event
  indices, per-event reaction times, counts, and — once epoched — the trial
  indices in the stack).

---

## Statement shape

```
bin <number> "<label>" [:] <expression>
```

- `<number>` — the bin index, an integer (`1`, `2`, …).
- `"<label>"` — a quoted description of the bin.
- `:` — **optional** separator between the label and the expression.
- `<expression>` — the predicate (see below).

Write one statement per line. An expression may also spill across several
lines; a new statement simply begins at the next `bin` (or `epoch`) keyword.

Comments run from `%` or `#` to the end of the line, and may sit on their own
line or after an expression:

```
% N400: prime-target pairs with a plausible response
epoch [-200,800] ms
bin 1 "Related"   : 112 and next(118) within (200,1200] ms   # in RT window
```

---

## Epoching (the `epoch` statement)

To segment the data, add a single `epoch` statement giving the window to cut
around every matched event:

```
epoch [-200,800] ms
```

- The window uses the same interval syntax as relation windows: bounds in
  `( )` / `[ ]`, an optional `ms` (default) or `samples` unit, and signed
  values (negative = before the event). `[-200,800] ms` means "from 200 ms
  before to 800 ms after the time-locking event", with t = 0 at the event.
- There is **at most one** `epoch` statement and it applies to **all** bins —
  every bin is cut with the same window. (Giving two `epoch` statements is an
  error.)
- Order does not matter; the `epoch` line may sit above or below the bins.

With an `epoch` statement, the result is a segmented dataset
(`channels × time × trials`, `DataFormat = "EPOCHED"`) that plots trial-by-trial
in EpochView. Every matched event becomes one trial; an event that satisfies
several bins is a **single** trial carrying all those bin tags (no data is
duplicated). Windows that run past the start or end of the recording are padded
with `NaN`. Each bin then also records the trial indices it owns in
`EEG.bindesc(b).trials`, ready for a later per-bin average.

Without an `epoch` statement, `DefineBins` leaves the data continuous and only
writes the bin tags — useful if you want to inspect or edit the tagging before
committing to a window.

---

## Codes (markers)

A **code** identifies an event marker. Two kinds:

| Kind | Written as | Matches |
|------|-----------|---------|
| Numeric | `112` (bare, no quotes) | event marker `112` or `"112"` |
| Text | `"S201"` (quoted) | event marker `S201` |

Matching is **case-insensitive**, and surrounding/internal whitespace in a
marker is ignored (so the code `"S 12"` matches an event marked `S12` or
`S 12`). Numeric codes also match by value, so `112` matches whether the
dataset stores the marker as the number `112` or the text `"112"`.

> Text markers **must be quoted**. Bare words are reserved for numbers and for
> the language's own keywords (`and`, `or`, `not`, `next`, …). If you write a
> text marker without quotes you get a clear error telling you to quote it.

### Wildcards

A quoted marker may contain wildcards:

| Wildcard | Matches |
|----------|---------|
| `?` | exactly one character |
| `*` | any run of characters (including none) |

So `"s??"` matches every marker that is `s` followed by **exactly two**
characters (e.g. `s11`, `s77`) but not `s1` or `s123`; `"s*"` matches any
marker beginning with `s`. Wildcards must be inside quotes (a numeric pattern
like `"1??"` therefore needs quoting too), and, like all matching, are
case-insensitive.

### Sets of codes

Anywhere a single code is allowed, you may give a **set** of alternatives,
matched if the event is any one of them. Two equivalent notations:

```
% pipe form — compact for a few codes
111|112|121|122

% braced list — reads well for many codes; spaces and/or commas separate
{"s11" "s22" "s33" "s44" "s55"}
{111, 112, 121, 122}
```

Sets work for anchors **and** inside relations, e.g. `next({"S201" "S202"})`.

---

## Terms

An expression is built from two kinds of terms.

### 1. Anchor — "this event is one of these codes"

A bare code or code-set. It constrains which events can time-lock the bin.

```
bin 1 "All targets"        : 112
bin 2 "Targets or probes"  : 112|122
bin 3 "Any of five stimuli": {"s11" "s22" "s33" "s44" "s55"}
```

### 2. Relation — "a neighbouring event stands in some relation to this one"

Relations look at events **around** the anchor. All delays are **signed and
measured from the anchor**: positive = later, negative = earlier.

| Relation | Meaning |
|----------|---------|
| `next(code)` | the nearest **following** event of that code (skipping any events in between) |
| `prev(code)` | the nearest **preceding** event of that code |
| `adjacent(code)` | the **immediately next** event (whatever it is) must be that code |
| `any(code) within (…)` | **some** event of that code exists inside the window |

`next` / `prev` / `adjacent` may optionally take a window; `any` **requires**
one.

```
bin 1 "Target then response"     : 112 and next(118)
bin 2 "Response then target"     : 112 and prev(118)
bin 3 "Target immediately gated" : 112 and adjacent(118)
bin 4 "Probe near a cue"         : 122 and any(200) within (-500,500] ms
```

---

## Windows

A window restricts a relation's signed delay.

```
within (200,1200] ms
within [-1200,-200) ms
within (0,300] samples
```

- **Bounds** — `(` and `)` are **exclusive**, `[` and `]` are **inclusive**.
  So `(200,1200]` means *strictly greater than 200 and up to and including
  1200*.
- **Unit** — `ms` (default if omitted) or `samples`.
- **Sign** — positive = after the anchor, negative = before. A window like
  `[-1200,-200)` therefore describes a neighbour *before* the anchor.
- The low bound may not exceed the high bound.

**How the window interacts with each relation:**

- `next(code) within W` — find the nearest following event of `code`; the
  relation is true only if **that** neighbour falls in `W`. It does **not**
  skip past a too-early/too-late neighbour to find a later match.
- `prev`/`adjacent` behave the same way with their identified neighbour.
- `any(code) within W` — true if **any** event of `code` lies in `W`.

Numbers may be decimals (`within (0.5,2.5] ms`) as well as integers.

---

## Combining terms

Use `and`, `or`, `not`, and parentheses. Precedence is the usual one:
`not` binds tightest, then `and`, then `or`. Group with `( )` to override.

```
bin 1 "Related, answered"    : 112 and next(118) within (200,1200] ms
bin 2 "Related, no answer"   : 112 and not next(118) within (0,2000] ms
bin 3 "Either stimulus, answered":
        (112 or 122) and next(118) within (200,1200] ms
bin 4 "Answered but not too fast":
        112 and next(118) within (200,1200] ms and not next(118) within (0,200] ms
```

`not R` inverts a relation: `not next(118) within (0,2000] ms` is true for an
anchor that has **no** following 118 within two seconds. It applies to a code
set just as well: `not {"s11" "s22" "s33" "s44" "s55"}` is true for any event
**not** in that set.

**Adjacent terms are `and`-ed.** Writing `and` between two terms is optional —
placing them next to each other means the same thing. This lets an
"everything except" bin read naturally:

```
% every two-character s-stimulus that is NOT in the related set, answered
bin 2 "Unrelated" "s??" not {"s11" "s22" "s33" "s44" "s55"} and next("S201") within (200,1200] ms
```

Here `"s??" not {…}` is `"s??" and not {…}`: the `"s??"` wildcard selects the
two-character stimuli, and `not {…}` removes the related ones.

---

## Reaction times

When a bin matches an event, `DefineBins` records the **delay to the
neighbour** picked out by the first relation in the expression, in
milliseconds, in `EEG.bindesc(b).rt` (aligned with `.events`). This gives you
response times for free — useful for later RT splits or median-split bins.

- The delay comes from the first (left-to-right) relation that contributed to
  the match. With `or`, it is taken from a branch that was actually true.
- If a matched bin has no relation (a pure anchor bin) or the contributing
  term was a `not`, the recorded RT is `NaN`.

Example — the interactive summary reports, per bin, the count and mean delay:

```
bin 1 "Related": 148 events  (mean delay 623 ms)
```

---

## Worked example (N400-style)

Prime–target pairs with a button-press response; stimulus markers `112`
(related) and `122` (unrelated), response marker `118`:

```
% --- N400 bins -------------------------------------------------------------
epoch [-200,800] ms                     % one window, shared by every bin

bin 1 "Related, in-window response"   : 112 and next(118) within (200,1200] ms
bin 2 "Unrelated, in-window response" : 122 and next(118) within (200,1200] ms

% Trials with no (timely) response — for exclusion or a separate ERP
bin 3 "Related, no response"   : 112 and not next(118) within (0,2000] ms
bin 4 "Unrelated, no response" : 122 and not next(118) within (0,2000] ms

% Collapsed across relatedness, answered only
bin 5 "All targets, answered" : (112|122) and next(118) within (200,1200] ms
```

The braced-list form is handy when a condition spans many stimulus codes:

```
bin 1 "Related" {"s11" "s22" "s33" "s44" "s55"} and next("S201") within (200,1200] ms
```

---

## Quick reference

```
script      : ( <bin> | <epoch> )+                      % one epoch at most
bin         : bin <int> "<label>" [:] <expr>
epoch       : epoch <window>                            % shared by all bins
expr        : expr or expr | expr [and] expr | not expr | ( expr )
            | <anchor> | <relation>          % 'and' optional between terms
anchor      : <codeset>
relation    : next( <codeset> ) [within <window>]
            | prev( <codeset> ) [within <window>]
            | adjacent( <codeset> ) [within <window>]
            | any( <codeset> ) within <window>          % window required
codeset     : <code> ( '|' <code> )*                    % pipe form
            | '{' <code> [ , ] <code> … '}'             % braced list
code        : <integer> | "<text marker>"               % ? = any char, * = any run
window      : ( '(' | '[' ) <num> , <num> ( ')' | ']' ) [ ms | samples ]
comment     : % … end-of-line   |   # … end-of-line
```

Delays in windows are signed and measured from the anchor (+ = later).
Parse errors report the column, e.g. `Parse error near column 32: expected ')'.`
