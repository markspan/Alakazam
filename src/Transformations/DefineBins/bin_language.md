# The bin-definition language

`DefineBins` assigns events to **bins** using a small, readable language, in
place of the ERPLAB EVENTLIST + BINLISTER step. Each bin is one statement:
a predicate over the events in the recording. Every event that satisfies it
becomes a time-locked point (t = 0) for that bin.

This document builds the language up from the simplest possible bin to a
full multi-bin script, one idea at a time. For the formal grammar, jump to
the [quick reference](#quick-reference) at the end.

---

## 1. Your first bin

```
bin 1 "Targets" 112
```

That's it: a bin number, a quoted label, and a **code** , the marker that
identifies an event. Every event marked `112` (or `"112"`; numeric codes
match either form) now belongs to bin 1.

## 2. Several codes

```
bin 1 "Targets or probes" 112|122
bin 2 "Any of five stimuli" {"s11" "s22" "s33" "s44" "s55"}
```

Pipe-separated (`|`) is compact for a few codes; a braced list reads better
for many. They're interchangeable , use whichever is more readable. A code
may also be a quoted marker with wildcards: `?` (exactly one character) or
`*` (any run), e.g. `"s??"` matches `s11`, `s77`, ... but not `s1` or `s123`.
Matching is always case-insensitive.

## 3. A relation to a neighbouring event

```
bin 1 "Target then response" 112 and next(118)
```

An **anchor** (like `112`) constrains the event itself; a **relation** looks
at its neighbours. `next(118)` is true when *some* `118` follows, however far
away. The other relations:

| Relation | True when |
|---|---|
| `next(code)` | the nearest **following** event of that code exists |
| `prev(code)` | the nearest **preceding** event of that code exists |
| `adjacent(code)` | the very next event (whatever it is) is that code |
| `any(code) within W` | some event of that code exists inside window `W` |

## 4. Constraining the relation to a window

```
bin 1 "Answered in time" 112 and next(118) within (200,1200] ms
```

Now it's only true if that following `118` lands strictly after 200 ms and
up to and including 1200 ms later. Windows are **signed** (+ = after the
anchor, − = before) and explicit about open/closed bounds:

```
within (200,1200] ms     % > 200 and <= 1200
within [-1200,-200) ms   % before the anchor: >= -1200 and < -200
within (0,300] samples   % sample counts instead of ms
within [-2,-2] events    % ordinal event count instead of elapsed time
```

`any(...)` *requires* a window (there's no natural neighbour to default to);
`next`/`prev`/`adjacent` treat it as optional.

### A fourth unit: `events`

`ms`/`samples` windows measure elapsed *time*; `events` measures ordinal
*position* in the event stream instead, counting the candidate event itself
as 0. `within [-2,-2] events` means "exactly two events back" — the
relation's own direction (`next`/`prev`) still decides which way to search,
`events` just changes what the window is measured in.

This matters whenever a time-based window would need to be wide enough to
absorb some jitter (a variable RT, a self-paced ITI) but that same width then
risks reaching past the trial you actually meant and into an earlier one.
Counting events instead sidesteps the jitter entirely, e.g. finding "the
stimulus that started the immediately preceding trial" in a strict
stimulus → response → stimulus → response design:

```
let precededByRare = prev(rare) within [-2,-2] events
```

whatever the gap in milliseconds happened to be on that particular trial.



## 5. Combining terms: `and` / `or` / `not`

```
bin 1 "Related, answered"     112 and next(118) within (200,1200] ms
bin 2 "Related, no answer"    112 and not next(118) within (0,2000] ms
bin 3 "Either stimulus"       (112 or 122) and next(118) within (200,1200] ms
```

Precedence is the usual one (`not` tightest, then `and`, then `or`); group
with `( )` to override. **Adjacent terms are `and`-ed even without the
keyword** , `112 next(118)` means exactly `112 and next(118)` , which reads
nicely for "everything except":

```
bin 4 "Unrelated" "s??" not {"s11" "s22" "s33"} and next("S201") within (200,1200] ms
```

(`"s??" not {...}` = "a two-character s-stimulus that is *not* one of
these".)

## 6. Reaction time, for free

Whenever a bin matches via a relation, `DefineBins` records the signed delay
to that neighbour as the reaction time, in `EEG.bindesc(b).rt` , no extra
syntax needed. Filter on it with `rt within`:

```
bin 1 "Fast responses" 112 and next(118) rt within (200,500] ms
bin 2 "Slow responses" 112 and next(118) rt within (500,1200] ms
```

This is a **post-filter** on the already-computed RT, not another relation ,
a match with no RT (a pure anchor bin, or one reached through `not`) is
dropped by an `rt within` filter.

## 7. Cutting epochs (the GUI fields, not the language)

The time window to cut around each matched event is **not** written in the
script , it's the two **Epoch start (ms)** / **Epoch stop (ms)** fields
above the editor, shared by every bin, e.g. `-200` and `800`. Leave both
blank to keep the data continuous (tag bins only, no segmenting); fill both
to get a segmented (`channels × time × trials`) dataset. The values, and the
script, are remembered between runs; **Save.../Load...** write/read both
together as a `.binscript` file.

## 8. Response-locking with `timelock`

By default a bin's epoch centres on the anchor. `timelock <relation>`
re-centres it on a neighbour instead:

```
bin 1 "Response-locked" 112 and next(118) timelock next(118)
```

Membership is still decided by the expression; `timelock` only moves where
t = 0 falls. A match with no neighbour to lock onto is dropped.

## 9. Naming things with `let`

```
let related = {"s11" "s22" "s33" "s44" "s55"}

bin 1 "Related"   related   and next("S201") within (200,1200] ms
bin 2 "Unrelated" "s??" not related and next("S201") within (200,1200] ms
```

`let <name> = <anything a bin could contain>` names a reusable piece of
script. It may be a code set, combined with `not`/`and`/`or` like `unrelated`
above, and it may reference **any alias defined earlier** in the script.

## 10. An alias can hold a relation, too

```
let answered = next(118) within (200,1200] ms

bin 1 "Related"   112 and answered
bin 2 "Unrelated" 122 and answered
```

This is the main reason to reach for `let`: it de-duplicates the part that's
usually repeated verbatim across several bins. A relation inside an alias
means exactly what it would mean written out inline at the reference site ,
including RT capture , whether that's directly in a bin, or as the argument
to another relation (`next(answered)`, testing whether a *neighbour*
satisfies it).

## 11. Difference bins

```
bin 1 "Related"   112 and next(118) within (200,1200] ms
bin 2 "Unrelated" 122 and next(118) within (200,1200] ms
bin 3 "N400 effect" = bin 2 - bin 1
```

`= <sum/difference of bin numbers>` builds a bin from **other bins'
averages** instead of an event predicate , there's no `:`/expression at all.
It has no trials of its own: `Average` averages the ordinary bins first,
then forms the combination, propagating the standard error as the root of
the summed squared errors. Since the terms are matched on different anchors,
they typically carry different trial counts (74 vs 68, say) , the legend
shows this as `N400 effect (n=68-74)` rather than a misleading "0 trials".

## 12. Interaction effects: combination bins referencing combination bins

```
bin 1 "Related, expected"     112 and next(118) within (200,1200] ms
bin 2 "Unrelated, expected"   122 and next(118) within (200,1200] ms
bin 3 "Related, unexpected"   113 and next(118) within (200,1200] ms
bin 4 "Unrelated, unexpected" 123 and next(118) within (200,1200] ms

bin 5 "Relatedness, expected"   = bin 2 - bin 1
bin 6 "Relatedness, unexpected" = bin 4 - bin 3
bin 7 "Relatedness x Expectancy" = bin 6 - bin 5
```

A combination bin may reference **another** combination bin , a
difference-of-differences, e.g. an interaction effect in a factorial design.
Declaration order doesn't matter (bin 7 could equally be written before bin
5/6); nesting is arbitrarily deep. A combination bin referencing itself,
directly or through a chain of others, or a bin number that doesn't exist,
is caught immediately when the script is parsed.

---

## Reference

### Codes and matching

| Kind | Written as | Matches |
|---|---|---|
| Numeric | `112` | marker `112` or `"112"` |
| Text | `"S201"` | marker `S201` (must be quoted , a bare word is an identifier/alias name) |

Wildcards (`?` one char, `*` any run) only work inside quotes, so a numeric
pattern like `"1??"` needs quoting too. Whitespace inside a marker is
ignored, so `"S 12"` matches `S12` or `S 12`.

### Sets

```
111|112|121|122                          % pipe form
{"s11" "s22" "s33" "s44"}                % braced list, spaces or commas
```

Work anywhere a code is allowed, including inside a relation:
`next({"S201" "S202"})`.

### Aliases (`let`)

- The right-hand side is any bin expression: codes, `not`/`and`/`or`,
  relations, or a mix.
- May reference any **other alias already defined earlier** in the script;
  referencing an undefined name, or itself, is an "unknown name" error.
- May be used anywhere a term or a code set is allowed: as a whole anchor,
  combined with other terms (`112 and answered`, or just `112 answered`),
  or as a relation's own argument (`next(related)`).
- Each name must be defined once.

### Combination bins

```
bin <n> "<label>" = [+|-] bin <n2> ( [+|-] bin <n3> )*
```

A signed sum of bin numbers (integer coefficients allowed: `2*bin 1 - bin
2`), each of which may itself be an ordinary or a combination bin. See
[§11](#11-difference-bins) and [§12](#12-interaction-effects-combination-bins-referencing-combination-bins).

### Reaction time and `rt within`

`EEG.bindesc(b).rt` holds the delay to the neighbour picked out by the first
(left-to-right) relation that contributed to the match (from a true branch,
if it went through `or`); `NaN` for a pure-anchor match or one from a `not`.
`rt within (lo,hi] ms` keeps only matches whose RT falls in that window
(`ms` only; a `NaN` RT is always dropped).

### Comments

`%` or `#` to end of line, on their own line or after an expression.

### Save.../Load...

Writes/reads the epoch bounds and the script together as one `.binscript`
file: a `% epoch_start_ms: …` / `% epoch_stop_ms: …` header, then the script
text. A plain script file with no header loads fine too , the epoch fields
are just left as they were.

### Errors

Every parse error shows the exact line, a caret under the mistake, and a
plain-language explanation of what went wrong and how to fix it (usually
with an example) , not just a bare "column 32" reference. A handful of
higher-level checks (a script with no bins, a combination bin cycle, a
dataset with no epoch-able data) are reported the same way even without a
single column to point at.

---

## Full worked example (N400-style)

Prime–target pairs with a button-press response; `112`/`113` = related
(expected/unexpected block), `122`/`123` = unrelated, `118` = response.
Epoch fields: `-200` / `800`.

```
% --- N400 bins, expected vs. unexpected block -----------------------------
let answered = next(118) within (200,1200] ms

bin 1 "Related, expected"     112 and answered
bin 2 "Unrelated, expected"   122 and answered
bin 3 "Related, unexpected"   113 and answered
bin 4 "Unrelated, unexpected" 123 and answered

% Trials with no (timely) response, for exclusion or a separate ERP
bin 5 "Related, no response" (112|113) and not next(118) within (0,2000] ms

% The relatedness effect, per block, and their interaction
bin 6 "Relatedness, expected"    = bin 2 - bin 1
bin 7 "Relatedness, unexpected"  = bin 4 - bin 3
bin 8 "Relatedness x Expectancy" = bin 7 - bin 6

% Response-locked view of the answered related trials
bin 9 "Related, response-locked" 112 and answered timelock next(118)
```

---

## Quick reference

```
script      : ( <let> | <bin> )+                        % epoch set in the GUI fields
let         : let <name> = <expr>                       % may use earlier let names
bin         : bin <int> "<label>" [:] <expr> [timelock <relation>] [rt within <window>]
            | bin <int> "<label>" = <combo>              % combination bin (may nest)
combo       : [ coeff ] bin <int> ( ('+'|'-') [ coeff ] bin <int> )*
expr        : expr or expr | expr [and] expr | not expr | ( expr )
            | <anchor> | <relation>          % 'and' optional between terms
anchor      : <codeset>
relation    : next( <codeset> ) [within <window>]
            | prev( <codeset> ) [within <window>]
            | adjacent( <codeset> ) [within <window>]
            | any( <codeset> ) within <window>          % window required
codeset     : <code> ( '|' <code> )*                    % pipe form
            | '{' <code> [ , ] <code> … '}'             % braced list
            | <name>                                    % a 'let' alias (any expr, incl. relations)
code        : <integer> | "<text marker>"               % ? = any char, * = any run
window      : ( '(' | '[' ) <num> , <num> ( ')' | ']' ) [ ms | samples | events ]
comment     : % … end-of-line   |   # … end-of-line
```

Delays in windows are signed and measured from the anchor (+ = later).
