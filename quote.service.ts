import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import { CreateQuoteResponse, Quote, QuoteRequest } from '../models/quote.model';

const API = environment.apiBaseUrl;

// QuoteService client (doc §6.3). POST creates AND persists the quote;
// ownership comes from the caller's token, never from the request body.
// The normalize* helpers adapt whatever field names the backend actually
// ships into the UI's canonical model — so the templates stay simple.
@Injectable({ providedIn: 'root' })
export class QuoteService {
  private readonly http = inject(HttpClient);

  /** FR3.1/FR3.2 — estimate + persist; response includes the alternate-tier estimate. */
  create(body: QuoteRequest): Observable<CreateQuoteResponse> {
    return this.http.post<unknown>(`${API}/quotes`, body).pipe(map(normalizeCreate));
  }

  /** Caller's own quotes (EffectiveStatus already applied by the server). */
  mine(): Observable<Quote[]> {
    return this.http.get<unknown[]>(`${API}/quotes/company`).pipe(map((qs) => (qs ?? []).map(normalizeQuote)));
  }

  get(id: string): Observable<Quote> {
    return this.http.get<unknown>(`${API}/quotes/${id}`).pipe(map(normalizeQuote));
  }

  /** FR3.4 — echoes stored inputs for InsuranceService to cross-check on apply. */
  convert(id: string): Observable<unknown> {
    return this.http.post(`${API}/quotes/${id}/convert`, {});
  }
}

type Raw = Record<string, any>;

function num(...cands: unknown[]): number {
  for (const c of cands) if (typeof c === 'number') return c;
  return 0;
}
function str(...cands: unknown[]): string {
  for (const c of cands) if (typeof c === 'string' && c.length) return c;
  return '';
}

function normalizeQuote(q: Raw): Quote {
  return {
    id: str(q.id),
    quoteNumber: str(q.quoteNumber),
    fleetSize: num(q.fleetSize),
    tier: str(q.tier),
    addOns: Array.isArray(q.addOns)
      ? (q.addOns as string[])
      : typeof q.addOns === 'string' && q.addOns.length
        ? (q.addOns as string).split(',').map((s) => s.trim())
        : [],
    premiumInr: num(q.premiumInr, q.estimatedPremiumInr, q.premium, q.totalPremiumInr),
    estimatedPremiumUsd: num(q.estimatedPremiumUsd, q.premiumUsd),
    estimatedPremiumEur: num(q.estimatedPremiumEur, q.premiumEur),
    usedFallbackRate: Boolean(q.usedFallbackRate),
    status: str(q.status, q.effectiveStatus),
    createdAtUtc: str(q.createdAtUtc, q.createdAt),
    expiresAtUtc: str(q.expiresAtUtc, q.validUntil, q.validUntilUtc, q.expiryUtc, q.expiresAt),
  };
}

function normalizeCreate(res: Raw): CreateQuoteResponse {
  const qRaw: Raw = res.quote ?? res; // wrapped { quote, alternateTier } or bare quote
  const alt: Raw = res.alternateTier ?? qRaw.alternateTier ?? {};
  return {
    quote: normalizeQuote(qRaw),
    alternateTier: {
      tier: str(alt.tier),
      premiumInr: num(alt.premiumInr, alt.estimatedPremiumInr),
    },
  };
}
