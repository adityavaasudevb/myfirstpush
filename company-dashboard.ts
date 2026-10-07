import { Component, inject, signal, ChangeDetectionStrategy } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';
import { CompanyProfileService } from '../../company-profile/services/company-profile.service';
import { QuoteService } from '../../../core/services/quote.service';
import { PolicyService } from '../../../core/services/policy.service';
import { ClaimsApiService } from '../../../core/services/claims-api.service';

@Component({
  selector: 'app-company-dashboard',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './company-dashboard.html',
  styleUrl: './company-dashboard.css',
})
export class CompanyDashboard {
  readonly auth = inject(AuthService);
  // The profile guard already loaded this by the time we render.
  readonly profile = inject(CompanyProfileService);

  private readonly quotes = inject(QuoteService);
  private readonly policies = inject(PolicyService);
  private readonly claims = inject(ClaimsApiService);

  /** Roll-up stats from each list's server-side total (page 1 = 1 item). */
  readonly quotesTotal = signal<number | null>(null);
  readonly activePolicies = signal<number | null>(null);
  readonly pendingPayments = signal<number | null>(null);
  readonly claimsTotal = signal<number | null>(null);

  constructor() {
    // Each call is independent — a failure just leaves that tile as "—".
    this.quotes.mine(1).subscribe({ next: (pg) => this.quotesTotal.set(pg.total), error: () => undefined });
    this.policies.mine({ status: 'Active', page: 1 }).subscribe({ next: (pg) => this.activePolicies.set(pg.total), error: () => undefined });
    this.policies.mine({ status: 'Pending', page: 1 }).subscribe({ next: (pg) => this.pendingPayments.set(pg.total), error: () => undefined });
    this.claims.mine({ page: 1 }).subscribe({ next: (pg) => this.claimsTotal.set(pg.total), error: () => undefined });
  }
}
