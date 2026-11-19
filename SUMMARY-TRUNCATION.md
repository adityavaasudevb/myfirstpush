# "The claim records agree on claim number CL"

That summary is truncated output, not a bug in your code.

## What happened

`SummariseAsync` in `GeminiAiProvider`:

```csharp
generationConfig = new { temperature = 0.2, maxOutputTokens = 200 }
```

The model answered in prose. It hit the 200-token ceiling mid-sentence and stopped. The provider
take the text as-is:

```csharp
return text is null ? Fail(...) : Ok(text.Trim(), ...);
```

There is no check that the answer is a complete sentence, and no check that it is even on-topic. So
`"The claim records agree on claim number CL"` is what a half-written sentence looks like.

Two clues that this is the whole story:

- `outputTokens: 3` on GFW103 — three tokens produced `"Claim details record"`. A real summary is
  ~40. The model was starved, not creative.
- `outputTokens: 8` on GFW104 — `"The claim records agree on claim number CL"`.

Also worth noting: the prompt asks for the summary *before* extraction results exist in a failed run,
so the facts JSON is thin. The model had almost nothing to summarise and still tried.

## The fix

Two changes in `GeminiAiProvider.SummariseAsync`:

```csharp
generationConfig = new { temperature = 0.2, maxOutputTokens = 400 }   // was 200
```

and after the call:

```csharp
var (text, promptTokens, outputTokens) = await CallAsync(body, ct);
sw.Stop();

// A sentence that stops mid-word is worse than no sentence: it reads as a verdict.
var trimmed = text?.Trim();
if (trimmed is null || trimmed.Length < 20 || !trimmed.EndsWith('.'))
    return AiCallResult<string>.Fail("summary was empty or truncated", sw.ElapsedMilliseconds);
```

`ClaimAuditService` already falls back to `FallbackSummary` when the call fails, so a rejected
summary produces the honest sentence ("No document could be read…") instead of a fragment. That is
the right trade: no summary beats a misleading one.

Note the asymmetry: extraction already reads its ceiling from config

```csharp
maxOutputTokens = _config.GetValue("Ai:MaxOutputTokens", 1500),   // extraction
generationConfig = new { temperature = 0.2, maxOutputTokens = 200 }  // summary - hardcoded
```

so make the summary match, otherwise you cannot tune it without editing code:

```csharp
generationConfig = new
{
    temperature = 0.2,
    maxOutputTokens = _config.GetValue("Ai:SummaryMaxOutputTokens", 400)
}
```

The truncation check is what makes the bigger ceiling safe, because on its own a larger limit only
moves the cliff further out.

## Why this matters more than it looks

In the failed run, the summary said the claim records **agree**. Every document failed to open. The
verdict happened to be `NeedsReview` because of the missing-FIR warning, but the sentence told a
reader the opposite of the truth. That is exactly the failure mode the whole audit exists to prevent,
and it came from the one part of the system that is not deterministic.

Worth saying in the viva: the verdict is computed in C# and cannot be talked into anything; the
narrative is the model's, and the service treats it as untrusted input.
