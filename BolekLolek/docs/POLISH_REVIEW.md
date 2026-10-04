# Polish quality review: Qwen3.5 4B (Lolek) vs Kimi K3 (reference)

30 Polish prompts, two anonymous answers each (15/15 A/B balance), one native reader, 1-5 per answer.
Qwen answers were generated through the app's own code path (same session, same Polish system prompt, no tools) after the
"say what you cannot do" clause was added to Lolek's prompt. Raw scores: `polish-review-scores.json`, key: `polish-review-key.json`.

| | Qwen3.5 4B | Kimi K3 |
|---|---|---|
| Mean score | **2.67** (27 scored) | **3.90** (30 scored) |
| Preferred in a pair | 3 | 22 (5 ties) |
| Scored 2 or lower | 12 of 27 | 1 of 30 |

By category (Qwen / Kimi): grammar and inflection 2.2 / 4.5; assistant replies (phrasing a weather, calendar or spending result) 2.0 / 4.0;
short answers 2.0 / 4.0; chat 3.0 / 4.2; e-mails and SMS 2.8 / 3.6; knowledge 2.7 / 3.7; limits and honesty 3.0 / 4.0; summaries 3.0 / 3.5; style and tone 3.3 / 3.3.
Qwen matched or beat Kimi on 7 rows (style rewrite, one knowledge answer, simple e-mails, the minute-declension prompt).

Caveats: one reader, 30 prompts, three cells left unscored (chat-4 A, mail-2 B, mix-1 A), almost no error tags or notes, so the
numbers say how good, not why. Indicative, not a benchmark.

What it means for Lolek: a 4B model is fine for deciding what to do (tool scorecard 12/12) and weak at writing Polish. The weakest
categories are exactly what Lolek produces most: short replies that phrase a tool result.
