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
as 0. `within [-2,-2] events` means "exactly two events back": the
relation's own direction (`next`/`prev`) still decides which way to search,
`events` just changes what the window is measured in.

This matters whenever a time-based window would need to be wide enough to
absorb some jitter (a variable RT, a self-paced ITI) but that same width then
risks reaching past the trial you actually meant and into an earlier one.
Counting events instead sidesteps the jitter entirely, e.g. finding "the
stimulus that started the immediately preceding trial" in a strict
stimulus → response → stimulus → response design:

```
let rare = 112
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

### Trimming slow (or fast) responses at mean ± k SD

A bound of the window may also be relative to the bin's own reaction times:
`mean`, or `mean + k sd` / `mean - k sd`. The usual outlier rule, "drop
trials more than 2.5 standard deviations slower than the mean", is

```
bin 1 "Correct, RT trimmed" 112 and next(118) rt within (0, mean + 2.5 sd] ms
```

and a fixed floor for anticipations combines with it in the same window:

```
bin 1 "Correct, RT trimmed" 112 and next(118) rt within (150, mean + 2.5 sd] ms
bin 2 "Both tails"          112 and next(118) rt within [mean - 2.5 sd, mean + 2.5 sd] ms
```

The mean and standard deviation (the sample SD, n − 1) are computed from
the reaction times of **every trial the bin's condition matched in this
recording**, before the window is applied, once: it is a single trimming
pass, not repeated until nothing falls outside. Each bin and each
recording gets its own cutoff, so one script trims every participant at
their own mean + 2.5 SD when it is replayed, dragged onto another
recording, or applied to all raw files.

What the window came to is recorded per bin in `EEG.bindesc(b).rtTrim`
(`mean`, `sd`, `nRt`, the resolved `lo` and `hi` in ms, and how many trials
it `removed`), and the summary after the run shows it. A bin with fewer
than two reaction times has no standard deviation to compute the bound
from: it keeps no trials, and the summary says why rather than skipping
the rule without a word.

`mean` and `sd` mean something only inside a window's bounds, so they
remain free as `let` names. A median split, Tukey's fences, ranks and
logarithms, of reaction times and of fields alike, are in
[§14](#14-splits-ranks-and-logarithms).

## 7. Cutting epochs

```
epoch [-200,800] ms
bin 1 "Targets" 112
```

An `epoch` line sets the window cut around every matched event, shared by
all bins, in the same interval notation as a relation's window: `ms` (the
default) or `samples`, never `events`. An epoch starts at its first bound and
stops one sample before its second, as EEGLAB's `epoch.m` cuts it: `[-200,800]
ms` at 500 Hz is 500 samples, from -200 to 798 ms. (FieldTrip's trial
definitions usually keep the last sample too.) Round and square brackets mean
the same here. It can stand anywhere in the script, once.

The two **Epoch start (ms)** / **Epoch stop (ms)** fields above the editor
do the same job; when the script has an `epoch` line, the line wins, and the
summary after the run says so if the fields held something else. With no
`epoch` line and both fields blank, the data stays continuous: bins are
tagged, nothing is segmented. The fields and the script are remembered
between runs; **Save.../Load...** write/read both together as a `.binscript`
file. (Deconvolve, which fits against the continuous recording, ignores an
`epoch` line in its bins.)

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

## 13. Testing an event's own fields

An event can carry numbers of its own besides its code and latency. The
Heartbeats plugin, for one, gives every heartbeat its interval to the next
beat (`ibi`, in ms) and the heart rate that makes (`hr`, in beats a
minute). `field <name> within <window>` tests such a number on the
candidate event itself:

```
bin 1 "Long intervals"  "heartbeat" and field ibi within (1000,2000]
bin 2 "Short intervals" "heartbeat" and field ibi within (0,800]
bin 3 "Fast heart"      "heartbeat" field hr within [90,200]
```

It is a term like any other: it combines with codes and relations through
`and`, `or` and `not`, and a `let` may name it
(`let slow = field hr within [0,60)`). The window takes **no unit**: the
value is compared in the unit the event holds it in, so writing `ms` after
it is an error rather than a conversion that never happens.

A value that is not one real number (empty, `NaN`, text) lies in no window,
so the test is false for it. The Heartbeats plugin leaves the interval of
the last beat before a cut `NaN`, so that beat is in no interval-based bin;
under `not` it is in. A field that **no** event of the recording has is
refused with the fields the events do have, rather than giving an empty bin
without a word; most often it means a step was not run (Heartbeats before
DefineBins) or the name is mistyped (field names are case-sensitive).

`field` is read as a plain word, not a keyword, so an alias called `field`
keeps working: where one is defined, the alias wins.

## 14. Splits, ranks and logarithms

A bound of a window may also be a **statistic of the bin's own trials**,
for a reaction time and for a field alike: `mean`, `median` or a percentile
(`p25`, `p75`, any whole number from `p0` to `p100`), plus or minus a
number of `sd`, `iqr` or `mad`. A bound may also be `inf` or `-inf`. Two
more ways to look at a value: `rank(...)`, its **percentile rank** among
the bin's trials (0 to 100), and `log(...)`, its **natural logarithm**:

```
bin 1 "Fast half"       112 and next(118) rt within (0, median] ms
bin 2 "Slow half"       112 and next(118) rt within (median, inf) ms
bin 3 "Fastest quarter" 112 and next(118) rank(rt) within [0, 25]
bin 4 "Tukey's fences"  112 and next(118) rt within [p25 - 1.5 iqr, p75 + 1.5 iqr] ms
bin 5 "Log-trimmed"     112 and next(118) log(rt) within [mean - 2.5 sd, mean + 2.5 sd]
bin 6 "Long intervals"  "heartbeat" and rank(field ibi) within (50, 100]
bin 7 "Robust trim"     "heartbeat" and field ibi within [median - 3 mad, median + 3 mad]
```

**Which trials the statistics come from.** A test like these is about the
bin's trials as a whole: a reaction time (the delay to the event the bin's
relation captured), a rank, or a bound taken from statistics. Its
statistics and ranks are those of the trials **the rest of the bin**
matches, in the recording being processed: bins 1 and 2 take the median of
the same trials and so split them into halves, and every participant is
split at their own median when the script is replayed or applied to all raw
files. Two such tests in one bin each take the same trials, not what the
other left: in `rt within (0, median] ms and rank(rt) within (25, 100]`, the
median and the ranks are both those of every trial `112 and next(118)`
matched. An ordinary term, such as `field hr within [0, 100]`, does limit
the trials: in `"heartbeat" and field hr within [0, 100] and rank(field
ibi) within [0, 50]` the ranks are among the beats under 100 beats a
minute.

Such a test must be one of the conditions every trial meets: joined to the
rest of the bin with `and` (or written next to it), not inside `or` or
`not`, where no set of trials is defined. For the other trials, write the
opposite window: `rank(rt) within (50, 100]` rather than `not rank(rt)
within [0, 50]`. A `let` may name one, and is then used the same way.

**What the statistics are.**

| Word | Meaning |
|------|---------|
| `mean` | the mean |
| `median` | the median (the same as `p50`) |
| `p25`, `p75`, ... | the percentile as MATLAB's `prctile` has it (Hazen's definition: the sorted values are the 100(i − 0.5)/n percentiles, with straight lines between) |
| `sd` | the sample standard deviation (n − 1) |
| `iqr` | `p75` − `p25` |
| `mad` | the median absolute deviation from the median, times 1.4826, which makes it estimate the standard deviation of normally distributed values (Leys et al., 2013): `median ± 3 mad` is comparable to `mean ± 3 sd`, but not pulled by the outliers it is meant to find |
| `rank(...)` | 100 (r − 0.5) / n, with r the rank from 1 to n and tied values sharing the mean of their ranks, so that `rank(rt) within [0, 50]` and `rt within (0, median] ms` keep the same trials, ties at the median apart |
| `log(...)` | the natural logarithm; a value of 0 or less has none |

They are computed once, over the values that exist: a trial without one
(no reaction time, a missing or `NaN` field, a logarithm of 0) is in no
window. A reaction-time window is in milliseconds (`ms` may be written);
the windows of a field, a logarithm and a rank take **no unit**.

**What it came to.** `EEG.bindesc(b).filters` records, for every such test,
the test as written, how many values it was computed from, their `mean`,
`sd`, `median`, `iqr` and `mad`, the window it resolved to (`lo`, `hi`) and
how many trials it `removed`; the summary after the run says the same. A
bound that cannot be computed (no values, or one value and an `sd`) keeps
no trials, and the summary says why rather than skipping the rule without a
word. (A plain `rt within` window of numbers or `mean ± k sd` is recorded in
`rtTrim`, as before; see [§6](#6-reaction-time-for-free).)

`log`, `rank` and the words of the statistics are plain words, not
keywords: an alias of any of those names keeps working.

*Reference:* Leys, C., Ley, C., Klein, O., Bernard, P., & Licata, L. (2013).
Detecting outliers: Do not use standard deviation around the mean, use
absolute deviation around the median. *Journal of Experimental Social
Psychology, 49*(4), 764-766. https://doi.org/10.1016/j.jesp.2013.03.013

---

## Reference

### Codes and matching

| Kind | Written as | Matches |
|---|---|---|
| Numeric | `112` | marker `112`, `"112"`, `S112` or `S 112` |
| Text | `"R201"` | marker `R201` (must be quoted , a bare word is an identifier/alias name) |
| Range | `21-30` | every code from 21 to 30 inclusive, prefixed or not |

Wildcards (`?` one char, `*` any run) only work inside quotes, so a numeric
pattern like `"1??"` needs quoting too. Whitespace inside a marker is
ignored, so `"S 12"` matches `S12` or `S 12`.

**A leading `s` before a number is dropped.** BrainVision writes stimulus
markers as `S 12`, `S201` and so on, so the codes arrive as text even though
they are numbers with a prefix. Dropping it makes them numeric again, which
means they can be written unquoted, compared numerically, and covered by a
range: `21-30` matches `S21` through `S30`. The rule is applied to both
sides, so `S12`, `S 12`, `s12` and `12` are all the same code whether they
are written in a bin definition or recorded in the file.

Only `s`/`S` is dropped, and only when the rest is entirely digits (or
wildcards). Response markers keep their prefix, since `R 12` routinely
reuses the number of the stimulus it answers, and a text marker like `"S1a"`
is left alone. Wildcards lose the prefix too (`"s??"` becomes `"??"`), so a
pattern written that way now also matches an unprefixed two-digit code.

A **range** is numeric only, and is expanded to every code it covers, so
`21-30` is exactly the same as writing all ten out. Spaces around the dash
make no difference: `21-30`, `21 -30`, `21 - 30` and `21- 30` are the same
range. Event codes are never negative, so a bare `-30` is refused, and so is
a range that runs backwards (`30-21`) or one wider than 1000 codes.

### Sets

```
111|112|121|122                          % pipe form
{"s11" "s22" "s33" "s44"}                % braced list, spaces or commas
{21-30 99}                               % a range and a single code
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

A signed sum of bin numbers (numeric coefficients allowed, whole or
fractional, written next to the term with no operator: `2 bin 1 - bin 2`,
`0.5 bin 1 + 0.5 bin 2`), each of which may itself be
an ordinary or a combination bin. See
[§11](#11-difference-bins) and [§12](#12-interaction-effects-combination-bins-referencing-combination-bins).

### Reaction time and `rt within`

`EEG.bindesc(b).rt` holds the delay to the neighbour picked out by the first
(left-to-right) **forward** relation that contributed to the match (from a
true branch, if it went through `or`); `NaN` for a pure-anchor match, one
from a `not`, or one whose only relations look backwards. Only forward
matches count: a reaction time is the delay to a *later* event, so a
preceding-context relation such as `prev(cue)` never becomes the reaction
time however early in the bin it is written. (`timelock` is unaffected and
may still lock to a preceding event.)
`rt within (lo,hi] ms` keeps only matches whose RT falls in that window
(`ms` only; a `NaN` RT is always dropped). Either bound may be `mean` or
`mean ± k sd` instead of a number: the mean and sample SD of the RTs of all
the bin's matches in the recording being processed, before the window is
applied (see [§6](#6-reaction-time-for-free)). The resolved window is in
`EEG.bindesc(b).rtTrim`; a bin with fewer than two RTs, whose SD bound
cannot be computed, keeps no trials.

### Value tests

`<value> within <window>`, where the value is `rt`, `field <name>`, or
`log(...)` or `rank(...)` of either, and each bound is a number, `inf`,
`-inf`, or `mean`, `median` or `p<0-100>`, optionally `+` or `-` a number
of `sd`, `iqr` or `mad` (see [§14](#14-splits-ranks-and-logarithms)). A
test of a reaction time, a rank or a bound from statistics is about the
bin's trials as a whole: it must be joined to the rest of the bin with
`and`, and its statistics are those of the trials the rest of the bin
matches, each such test over the same trials. Any other value test (a field
or its logarithm against numbers) is an ordinary term, allowed anywhere. What
each test about the trials came to is in `EEG.bindesc(b).filters`; a plain
`rt within` window of numbers or `mean ± k sd` is in `rtTrim` instead.

### Comments

`%` or `#` to end of line, on their own line or after an expression. Apart
from comments, nothing may come before the first `bin`, `let` or `epoch`
statement: anything else there is an error, where it used to be dropped
without a word.

### Save.../Load...

Writes/reads the epoch bounds and the script together as one `.binscript`
file: a `% epoch_start_ms: …` / `% epoch_stop_ms: …` header, then the script
text. A plain script file with no header loads fine too: the epoch fields
are left as they were.

### Import BDF...

Reads an **ERPLAB bin descriptor file** (BINLISTER's `.txt`/`.bdf`) and
translates it into this language, filling the editor. The time-locking event
`.{a;b}` becomes the anchor `a|b`; a preceding bracket `{c}.{…}` becomes
`prev(c)`; a following bracket with a timing flag `.{…}{r:200<t<=800}` becomes
`next(r) within (200,800] ms`. Anything with no equivalent (write-back `w`,
flag conditions, open-ended `t>x`) is imported best-effort and flagged with a
`% WARNING:` line so you can finish it by hand. The epoch bounds are ERPLAB's
own separate step, so the two fields above are left untouched. The converter
is `erplabBdfToBinScript` (usable on its own for scripting).

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

```
% --- N400 bins, expected vs. unexpected block -----------------------------
epoch [-200,800] ms
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
script      : ( <let> | <bin> | <epoch> )+              % comments only before the first
epoch       : epoch <window>                            % ms or samples; at most once
let         : let <name> = <expr>                       % may use earlier let names
bin         : bin <int> "<label>" [:] <expr> [timelock <relation>] [ <value-test> ... ]
            | bin <int> "<label>" = <combo>              % combination bin (may nest)
combo       : [ coeff ] bin <int> ( ('+'|'-') [ coeff ] bin <int> )*
expr        : expr or expr | expr [and] expr | not expr | ( expr )
            | <anchor> | <relation> | <value-test>  % 'and' optional between terms
anchor      : <codeset>
value-test  : <value> within <value-window>   % rt, rank, statistics: and-ed at the top only
value       : rt | field <name> | log( rt | field <name> ) | rank( rt | field <name> )
value-window: ( '(' | '[' ) <bound> , <bound> ( ')' | ']' ) [ ms ]  % ms for rt alone
bound       : <num> | inf | -inf | <stat> [ ('+'|'-') <num> ( sd | iqr | mad ) ]
stat        : mean | median | p<0-100>                  % of the bin's own trials
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
