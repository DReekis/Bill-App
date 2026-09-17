/**
 * Billket Executive Cloud Admin - Frontend Application
 * Vanilla JS | Modern ES Modules | High Performance | Zero Framework Bloat
 */

// State Management
const state = {
  token: localStorage.getItem('billket_admin_token') || null,
  user: null,
  activeView: 'overview',
  refreshInterval: null,
  searchQuery: '',
  syncFilter: 'all',
};

// ==========================================
// Toast Notification System
// ==========================================
function showToast(message, type = 'success') {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      ${type === 'success' 
        ? '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline>' 
        : '<circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line>'
      }
    </svg>
    <span>${message}</span>
  `;

  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    toast.style.transition = 'all 0.25s ease';
    setTimeout(() => toast.remove(), 250);
  }, 3500);
}

// ==========================================
// Unified API Client
// ==========================================
async function api(endpoint, options = {}) {
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };

  if (state.token) {
    headers['Authorization'] = `Bearer ${state.token}`;
  }

  const startTime = performance.now();
  try {
    const res = await fetch(endpoint, {
      ...options,
      headers,
    });

    const elapsed = Math.round(performance.now() - startTime);
    updateLatencyIndicator(elapsed);

    if (res.status === 401 || res.status === 403) {
      if (endpoint !== '/api/v1/admin/login') {
        state.token = null;
        localStorage.removeItem('billket_admin_token');
        showAuthModal(true);
        showToast('Admin session expired. Please sign in.', 'error');
        throw new Error('Unauthorized');
      }
    }

    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || err.message || 'API request failed');
    }

    return await res.json();
  } catch (err) {
    updateLatencyIndicator(null);
    throw err;
  }
}

function updateLatencyIndicator(latencyMs) {
  const pill = document.getElementById('system-status-pill');
  const latencyEl = document.getElementById('ping-latency');
  if (!pill || !latencyEl) return;

  if (latencyMs !== null) {
    pill.classList.remove('offline');
    pill.querySelector('.status-label').textContent = 'Online';
    latencyEl.textContent = `${latencyMs}ms`;
  } else {
    pill.classList.add('offline');
    pill.querySelector('.status-label').textContent = 'Offline';
    latencyEl.textContent = '--';
  }
}

// ==========================================
// Auth Manager
// ==========================================
function initAuth() {
  const overlay = document.getElementById('auth-modal-overlay');
  const form = document.getElementById('form-admin-login');
  const btnQuick = document.getElementById('btn-fill-dev-creds');
  const errorMsg = document.getElementById('login-error-msg');
  const btnLogout = document.getElementById('btn-logout');

  if (!state.token) {
    showAuthModal(true);
  } else {
    loadAdminProfile();
  }

  form?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = document.getElementById('login-email').value.trim();
    const password = document.getElementById('login-password').value;

    errorMsg.style.display = 'none';
    const submitBtn = document.getElementById('btn-submit-login');
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="spinner"></span> Authenticating...';

    try {
      const data = await api('/api/v1/admin/login', {
        method: 'POST',
        body: JSON.stringify({ email, password }),
      });

      state.token = data.token;
      state.user = data.user;
      localStorage.setItem('billket_admin_token', data.token);

      showAuthModal(false);
      updateHeaderUser(data.user);
      showToast(`Welcome back, ${data.user.name}!`);
      loadCurrentView();
    } catch (err) {
      errorMsg.textContent = err.message || 'Invalid credentials or non-admin role';
      errorMsg.style.display = 'block';
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = '<span>Authenticate to Dashboard</span>';
    }
  });

  btnQuick?.addEventListener('click', async () => {
    // Fill credentials or register a local dev superadmin if none exists
    const emailInput = document.getElementById('login-email');
    const passInput = document.getElementById('login-password');
    emailInput.value = 'admin@pricepilot.in';
    passInput.value = 'admin123';

    // Auto-create local admin if needed
    try {
      await fetch('/api/v1/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: 'Executive SuperAdmin',
          email: 'admin@pricepilot.in',
          password: 'admin123',
        }),
      });
    } catch {}

    form.requestSubmit();
  });

  btnLogout?.addEventListener('click', () => {
    state.token = null;
    state.user = null;
    localStorage.removeItem('billket_admin_token');
    showAuthModal(true);
    showToast('Signed out of admin console');
  });

  // User Dropdown toggle
  const userBtn = document.getElementById('btn-user-profile');
  const dropdown = document.getElementById('user-dropdown-menu');
  userBtn?.addEventListener('click', (e) => {
    e.stopPropagation();
    dropdown?.classList.toggle('active');
  });

  document.addEventListener('click', () => {
    dropdown?.classList.remove('active');
  });

  document.getElementById('btn-trigger-backup-quick')?.addEventListener('click', async () => {
    try {
      const res = await api('/api/v1/admin/backups', { method: 'POST' });
      showToast(`Snapshot created: ${res.filename} (${res.sizeFormatted})`);
      if (state.activeView === 'health') loadCurrentView();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });
}

function showAuthModal(show) {
  const overlay = document.getElementById('auth-modal-overlay');
  if (overlay) overlay.style.display = show ? 'flex' : 'none';
}

async function loadAdminProfile() {
  try {
    const user = await api('/api/v1/admin/me');
    state.user = user;
    updateHeaderUser(user);
    loadCurrentView();
  } catch {
    showAuthModal(true);
  }
}

function updateHeaderUser(user) {
  if (!user) return;
  document.getElementById('header-user-name').textContent = user.name || 'Admin';
  document.getElementById('header-user-role').textContent = user.role || 'SuperAdmin';
  document.getElementById('dropdown-user-email').textContent = user.email || '';
  const initials = (user.name || 'AD')
    .split(' ')
    .map((n) => n[0])
    .join('')
    .substring(0, 2)
    .toUpperCase();
  document.getElementById('user-avatar-initials').textContent = initials;
}

// ==========================================
// Router & Navigation
// ==========================================
function initRouter() {
  window.addEventListener('hashchange', () => {
    handleHashChange();
  });

  document.getElementById('global-search-input')?.addEventListener('input', (e) => {
    state.searchQuery = e.target.value;
    if (state.activeView === 'businesses') {
      renderBusinessesView();
    } else if (e.target.value.length > 2) {
      window.location.hash = '#businesses';
    }
  });

  document.getElementById('btn-manual-refresh')?.addEventListener('click', () => {
    loadCurrentView();
    showToast('Refreshed console metrics');
  });

  handleHashChange();

  // Start periodic 15-second telemetry polling
  state.refreshInterval = setInterval(() => {
    if (state.token) {
      pingTelemetry();
    }
  }, 15000);
}

function handleHashChange() {
  const hash = window.location.hash.replace('#', '').trim() || 'overview';
  state.activeView = hash;

  // Update sidebar active link
  document.querySelectorAll('.sidebar-nav .nav-item').forEach((item) => {
    if (item.getAttribute('data-view') === hash) {
      item.classList.add('active');
    } else {
      item.classList.remove('active');
    }
  });

  loadCurrentView();
}

function loadCurrentView() {
  if (!state.token) return;

  const mount = document.getElementById('view-mount-point');
  if (!mount) return;

  mount.innerHTML = `
    <div class="view-loading-state">
      <div class="spinner"></div>
      <p>Fetching platform data...</p>
    </div>
  `;

  switch (state.activeView) {
    case 'overview':
      renderOverviewView();
      break;
    case 'businesses':
      renderBusinessesView();
      break;
    case 'subscriptions':
      renderSubscriptionsView();
      break;
    case 'sync':
      renderSyncView();
      break;
    case 'health':
      renderHealthView();
      break;
    case 'audit':
      renderAuditView();
      break;
    default:
      renderOverviewView();
  }
}

async function pingTelemetry() {
  try {
    const health = await api('/api/v1/admin/health');
    document.getElementById('sidebar-db-size').textContent = health.database.sizeFormatted;
    document.getElementById('sidebar-pending-sync-badge').textContent =
      health.database.recordCounts.syncQueueItems || 0;
  } catch {}
}

// ==========================================
// Views Implementation
// ==========================================

// --- VIEW 1: OVERVIEW ---
async function renderOverviewView() {
  const mount = document.getElementById('view-mount-point');
  try {
    const data = await api('/api/v1/admin/overview');
    const revenueInr = (data.totalRevenueCents / 100).toLocaleString('en-IN', {
      style: 'currency',
      currency: 'INR',
      maximumFractionDigits: 0,
    });

    mount.innerHTML = `
      <div class="view-header">
        <div class="view-title-group">
          <h1>Platform Operations Overview</h1>
          <p>Real-time telemetry across multi-business organizations, subscriptions, and sync queues</p>
        </div>
        <div class="view-actions">
          <button class="btn btn-secondary" id="btn-snap-now">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path><polyline points="17 21 17 13 7 13 7 21"></polyline><polyline points="7 3 7 8 15 8"></polyline></svg>
            <span>Create DB Snapshot</span>
          </button>
        </div>
      </div>

      <!-- KPI Grid -->
      <div class="kpi-grid">
        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Registered Businesses</span>
            <div class="kpi-icon-badge bg-indigo">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 21h18M3 7v14M21 7v14M6 21V11M10 21V11M14 21V11M18 21V11M9 7h6M12 3l9 4M12 3L3 7"></path></svg>
            </div>
          </div>
          <div class="kpi-value">${data.totalBusinesses}</div>
          <div class="kpi-footer">
            <span>Multi-tenant isolation active</span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Active Users</span>
            <div class="kpi-icon-badge bg-cyan">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path></svg>
            </div>
          </div>
          <div class="kpi-value">${data.totalUsers}</div>
          <div class="kpi-footer">
            <span>Across all roles & branches</span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Gross Processed Volume</span>
            <div class="kpi-icon-badge bg-emerald">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="1" x2="12" y2="23"></line><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path></svg>
            </div>
          </div>
          <div class="kpi-value">${revenueInr}</div>
          <div class="kpi-footer">
            <span>${data.totalInvoices} Invoices Generated</span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Cloud Sync Queue</span>
            <div class="kpi-icon-badge bg-amber">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.5 2v6h-6M2.5 22v-6h6M2 11.5a10 10 0 0 1 18.8-4.3M22 12.5a10 10 0 0 1-18.8 4.2"/></svg>
            </div>
          </div>
          <div class="kpi-value">${data.syncStats.pending} <span style="font-size: 0.9rem; font-weight: 500; color: var(--text-muted);">/ ${data.syncStats.total}</span></div>
          <div class="kpi-footer">
            <span>${data.syncStats.failed} failed items</span>
          </div>
        </div>
      </div>

      <!-- License & Tier Breakdown -->
      <div class="glass-panel">
        <div class="panel-header">
          <div>
            <h3 class="panel-title">Subscription Tier Distribution</h3>
            <p class="panel-subtitle">Active licensing across connected business profiles</p>
          </div>
          <a href="#subscriptions" class="btn btn-sm btn-ghost">Manage Tiers &rarr;</a>
        </div>
        <div style="padding: 1.25rem 1.5rem; display: flex; gap: 1.5rem; flex-wrap: wrap;">
          ${data.tierBreakdown.map((t) => `
            <div style="flex: 1; min-width: 180px; background: rgba(255, 255, 255, 0.02); border: 1px solid var(--border-subtle); border-radius: var(--radius-md); padding: 1rem;">
              <div style="font-size: 0.75rem; text-transform: uppercase; font-weight: 600; color: var(--text-muted);">${t.tier}</div>
              <div style="font-family: var(--font-display); font-size: 1.5rem; font-weight: 700; color: #FFF; margin-top: 0.25rem;">${t.count} Businesses</div>
            </div>
          `).join('')}
        </div>
      </div>

      <!-- Recent Audit Activity -->
      <div class="glass-panel">
        <div class="panel-header">
          <div>
            <h3 class="panel-title">Recent System Audit Trail</h3>
            <p class="panel-subtitle">Live log of administrative mutations and license changes</p>
          </div>
          <a href="#audit" class="btn btn-sm btn-ghost">View Full Log &rarr;</a>
        </div>
        <div class="table-responsive">
          <table class="admin-table">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Entity</th>
                <th>Business</th>
              </tr>
            </thead>
            <tbody>
              ${data.recentAudit.length ? data.recentAudit.map((a) => `
                <tr>
                  <td>${new Date(a.createdAt).toLocaleString('en-IN')}</td>
                  <td>
                    <span class="table-entity-title">${a.actor?.name || 'System Auto'}</span>
                    <span class="table-entity-sub">${a.actor?.email || 'daemon'}</span>
                  </td>
                  <td><span class="status-badge status-active">${a.action}</span></td>
                  <td>${a.entity}</td>
                  <td>${a.business?.name || 'Global'}</td>
                </tr>
              `).join('') : '<tr><td colspan="5" style="text-align: center; color: var(--text-muted);">No recent audit entries</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;

    document.getElementById('btn-snap-now')?.addEventListener('click', async () => {
      try {
        const snap = await api('/api/v1/admin/backups', { method: 'POST' });
        showToast(`Snapshot created: ${snap.filename}`);
      } catch (err) {
        showToast(err.message, 'error');
      }
    });
  } catch (err) {
    mount.innerHTML = `<div class="auth-error-banner">Failed to load overview: ${err.message}</div>`;
  }
}

// --- VIEW 2: BUSINESSES & USERS ---
async function renderBusinessesView() {
  const mount = document.getElementById('view-mount-point');
  try {
    const searchParam = state.searchQuery ? `?search=${encodeURIComponent(state.searchQuery)}` : '';
    const businesses = await api(`/api/v1/admin/businesses${searchParam}`);

    mount.innerHTML = `
      <div class="view-header">
        <div class="view-title-group">
          <h1>Organizations & Multi-Business Oversight</h1>
          <p>Monitor multi-tenant businesses, sales activity, and connected device quotas</p>
        </div>
      </div>

      <div class="glass-panel">
        <div class="panel-header">
          <div>
            <h3 class="panel-title">Registered Business Entities (${businesses.length})</h3>
            <p class="panel-subtitle">Full data isolation across local SQLite & cloud replicas</p>
          </div>
        </div>
        <div class="table-responsive">
          <table class="admin-table">
            <thead>
              <tr>
                <th>Business Name & City</th>
                <th>Owner & Contact</th>
                <th>GSTIN</th>
                <th>Tier & Status</th>
                <th>Volume & Invoices</th>
                <th>Customers / Items</th>
                <th>Last Sync</th>
                <th style="text-align: right;">Actions</th>
              </tr>
            </thead>
            <tbody>
              ${businesses.length ? businesses.map((b) => {
                const rev = (b.totalRevenueCents / 100).toLocaleString('en-IN', {
                  style: 'currency',
                  currency: 'INR',
                  maximumFractionDigits: 0,
                });
                const statusClass = b.subscriptionStatus === 'active' ? 'status-active'
                  : b.subscriptionStatus === 'trial' ? 'status-trial'
                  : b.subscriptionStatus === 'grace_period' ? 'status-grace' : 'status-expired';

                return `
                  <tr>
                    <td>
                      <span class="table-entity-title">${b.name}</span>
                      <span class="table-entity-sub">${b.city || 'Not set'}, ${b.state || 'India'}</span>
                    </td>
                    <td>
                      <span class="table-entity-title">${b.ownerName || b.owner?.name || 'Owner'}</span>
                      <span class="table-entity-sub">${b.phone || b.owner?.email || '--'}</span>
                    </td>
                    <td><code>${b.gstin || 'Unregistered'}</code></td>
                    <td>
                      <span class="status-badge ${statusClass}">${b.subscriptionTier} (${b.subscriptionStatus})</span>
                      <div style="font-size: 0.7rem; color: var(--text-muted); margin-top: 2px;">Max ${b.maxDevices} devices</div>
                    </td>
                    <td>
                      <span class="table-entity-title">${rev}</span>
                      <span class="table-entity-sub">${b.counts.invoices} bills</span>
                    </td>
                    <td>${b.counts.customers} parties / ${b.counts.products} items</td>
                    <td>
                      <span style="font-size: 0.75rem; color: ${b.lastSyncStatus === 'synced' ? '#10B981' : '#F59E0B'}">
                        ${b.lastSyncAt ? new Date(b.lastSyncAt).toLocaleTimeString() : 'Never'}
                      </span>
                    </td>
                    <td style="text-align: right;">
                      <button class="btn btn-sm btn-secondary btn-edit-sub" data-biz='${JSON.stringify(b)}'>
                        License Gate
                      </button>
                    </td>
                  </tr>
                `;
              }).join('') : '<tr><td colspan="8" style="text-align: center; color: var(--text-muted);">No businesses found</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;

    // Wire license gate buttons
    document.querySelectorAll('.btn-edit-sub').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        const b = JSON.parse(btn.getAttribute('data-biz'));
        openSubscriptionModal(b);
      });
    });
  } catch (err) {
    mount.innerHTML = `<div class="auth-error-banner">Failed to load businesses: ${err.message}</div>`;
  }
}

// --- VIEW 3: SUBSCRIPTIONS & LICENSE GATE ---
async function renderSubscriptionsView() {
  const mount = document.getElementById('view-mount-point');
  try {
    const businesses = await api('/api/v1/admin/businesses');

    mount.innerHTML = `
      <div class="view-header">
        <div class="view-title-group">
          <h1>Subscription Tiers & License Gate</h1>
          <p>Control device allowances, expiration cycles, and enforce read-only grace modes</p>
        </div>
      </div>

      <div class="glass-panel">
        <div class="panel-header">
          <div>
            <h3 class="panel-title">Business Subscription Roster</h3>
            <p class="panel-subtitle">Enforce plan capabilities & restrict offline synchronization if past due</p>
          </div>
        </div>
        <div class="table-responsive">
          <table class="admin-table">
            <thead>
              <tr>
                <th>Business</th>
                <th>Current Plan</th>
                <th>Status</th>
                <th>Device Quota</th>
                <th>Renewal / Expiry</th>
                <th style="text-align: right;">Actions</th>
              </tr>
            </thead>
            <tbody>
              ${businesses.map((b) => {
                const statusClass = b.subscriptionStatus === 'active' ? 'status-active'
                  : b.subscriptionStatus === 'trial' ? 'status-trial'
                  : b.subscriptionStatus === 'grace_period' ? 'status-grace' : 'status-expired';

                const expiryFormatted = b.subscriptionExpiresAt 
                  ? new Date(b.subscriptionExpiresAt).toLocaleDateString() 
                  : 'Never (Perpetual)';

                return `
                  <tr>
                    <td>
                      <span class="table-entity-title">${b.name}</span>
                      <span class="table-entity-sub">${b.ownerName || 'Owner'}</span>
                    </td>
                    <td><strong style="text-transform: uppercase; font-size: 0.8rem; color: #FFF;">${b.subscriptionTier}</strong></td>
                    <td><span class="status-badge ${statusClass}">${b.subscriptionStatus}</span></td>
                    <td>${b.maxDevices} Devices Allowed</td>
                    <td>${expiryFormatted}</td>
                    <td style="text-align: right;">
                      <button class="btn btn-sm btn-primary btn-edit-sub" data-biz='${JSON.stringify(b)}'>
                        Configure License
                      </button>
                    </td>
                  </tr>
                `;
              }).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `;

    document.querySelectorAll('.btn-edit-sub').forEach((btn) => {
      btn.addEventListener('click', () => {
        const b = JSON.parse(btn.getAttribute('data-biz'));
        openSubscriptionModal(b);
      });
    });
  } catch (err) {
    mount.innerHTML = `<div class="auth-error-banner">Failed to load subscriptions: ${err.message}</div>`;
  }
}

// --- VIEW 4: CLOUD SYNC MONITOR ---
async function renderSyncView() {
  const mount = document.getElementById('view-mount-point');
  try {
    const filter = state.syncFilter || 'all';
    const items = await api(`/api/v1/admin/sync/queue?status=${filter}&limit=100`);

    mount.innerHTML = `
      <div class="view-header">
        <div class="view-title-group">
          <h1>Cloud Synchronization Telemetry & Inspector</h1>
          <p>Real-time stream of incoming SQLite offline mutation payloads & conflict resolution</p>
        </div>
      </div>

      <div class="glass-panel">
        <div class="panel-header">
          <div>
            <h3 class="panel-title">Sync Queue Activity</h3>
            <p class="panel-subtitle">Inspecting latest ${items.length} records</p>
          </div>
          <div class="view-actions">
            <button class="btn btn-sm ${filter === 'all' ? 'btn-primary' : 'btn-ghost'} btn-sync-filter" data-f="all">All</button>
            <button class="btn btn-sm ${filter === 'pending' ? 'btn-primary' : 'btn-ghost'} btn-sync-filter" data-f="pending">Pending</button>
            <button class="btn btn-sm ${filter === 'synced' ? 'btn-primary' : 'btn-ghost'} btn-sync-filter" data-f="synced">Synced</button>
            <button class="btn btn-sm ${filter === 'failed' ? 'btn-primary' : 'btn-ghost'} btn-sync-filter" data-f="failed">Failed</button>
          </div>
        </div>
        <div class="table-responsive">
          <table class="admin-table">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>Business</th>
                <th>Entity & Op</th>
                <th>Entity ID</th>
                <th>Status</th>
                <th>Attempts</th>
                <th style="text-align: right;">Action</th>
              </tr>
            </thead>
            <tbody>
              ${items.length ? items.map((i) => `
                <tr>
                  <td>${new Date(i.createdAt).toLocaleTimeString()}</td>
                  <td><span class="table-entity-title">${i.business?.name || i.businessId}</span></td>
                  <td>
                    <span class="table-entity-title">${i.entity}</span>
                    <span class="table-entity-sub" style="text-transform: uppercase;">${i.op}</span>
                  </td>
                  <td><code>${i.entityId.substring(0, 16)}...</code></td>
                  <td>
                    <span class="status-badge ${i.status === 'synced' ? 'status-active' : i.status === 'pending' ? 'status-grace' : 'status-expired'}">
                      ${i.status}
                    </span>
                  </td>
                  <td>${i.attempts}</td>
                  <td style="text-align: right;">
                    <button class="btn btn-sm btn-ghost btn-inspect-sync" data-item='${JSON.stringify(i)}'>Inspect</button>
                    ${i.status !== 'synced' ? `<button class="btn btn-sm btn-secondary btn-retry-sync" data-id="${i.id}">Retry</button>` : ''}
                  </td>
                </tr>
              `).join('') : '<tr><td colspan="7" style="text-align: center; color: var(--text-muted);">No sync records found</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;

    document.querySelectorAll('.btn-sync-filter').forEach((b) => {
      b.addEventListener('click', () => {
        state.syncFilter = b.getAttribute('data-f');
        renderSyncView();
      });
    });

    document.querySelectorAll('.btn-inspect-sync').forEach((b) => {
      b.addEventListener('click', () => {
        const item = JSON.parse(b.getAttribute('data-item'));
        openInspectModal(item);
      });
    });

    document.querySelectorAll('.btn-retry-sync').forEach((b) => {
      b.addEventListener('click', async () => {
        const id = b.getAttribute('data-id');
        b.disabled = true;
        b.textContent = 'Retrying...';
        try {
          await api(`/api/v1/admin/sync/retry/${id}`, { method: 'POST' });
          showToast('Sync item processed successfully!');
          renderSyncView();
        } catch (err) {
          showToast(err.message, 'error');
          b.disabled = false;
          b.textContent = 'Retry';
        }
      });
    });
  } catch (err) {
    mount.innerHTML = `<div class="auth-error-banner">Failed to load sync queue: ${err.message}</div>`;
  }
}

// --- VIEW 5: HEALTH & BACKUPS ---
async function renderHealthView() {
  const mount = document.getElementById('view-mount-point');
  try {
    const [health, backups] = await Promise.all([
      api('/api/v1/admin/health'),
      api('/api/v1/admin/backups'),
    ]);

    mount.innerHTML = `
      <div class="view-header">
        <div class="view-title-group">
          <h1>System Health & Cloud Snapshots</h1>
          <p>Database metrics, Node.js process memory telemetry, and disaster recovery snapshots</p>
        </div>
        <div class="view-actions">
          <button class="btn btn-primary" id="btn-create-backup-view">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"></path><polyline points="17 21 17 13 7 13 7 21"></polyline><polyline points="7 3 7 8 15 8"></polyline></svg>
            <span>Trigger Atomic SQLite Backup</span>
          </button>
        </div>
      </div>

      <!-- Telemetry Cards -->
      <div class="kpi-grid">
        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Database File Size</span>
            <div class="kpi-icon-badge bg-indigo">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path></svg>
            </div>
          </div>
          <div class="kpi-value">${health.database.sizeFormatted}</div>
          <div class="kpi-footer">
            <span>SQLite WAL Mode Active</span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Process Memory (RSS)</span>
            <div class="kpi-icon-badge bg-emerald">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="2" width="20" height="8" rx="2" ry="2"></rect><rect x="2" y="14" width="20" height="8" rx="2" ry="2"></rect><line x1="6" y1="6" x2="6.01" y2="6"></line><line x1="6" y1="18" x2="6.01" y2="18"></line></svg>
            </div>
          </div>
          <div class="kpi-value">${health.system.memory.rssMb} <span style="font-size: 0.8rem; color: var(--text-muted);">MB</span></div>
          <div class="kpi-footer">
            <span>Heap: ${health.system.memory.heapUsedMb} MB / ${health.system.memory.heapTotalMb} MB</span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Server Uptime</span>
            <div class="kpi-icon-badge bg-amber">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline></svg>
            </div>
          </div>
          <div class="kpi-value">${Math.floor(health.uptimeSeconds / 60)}m ${health.uptimeSeconds % 60}s</div>
          <div class="kpi-footer">
            <span>Node ${health.system.nodeVersion} (${health.system.platform})</span>
          </div>
        </div>

        <div class="kpi-card">
          <div class="kpi-top">
            <span class="kpi-label">Total Cloud Records</span>
            <div class="kpi-icon-badge bg-rose">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline></svg>
            </div>
          </div>
          <div class="kpi-value">
            ${Object.values(health.database.recordCounts).reduce((a, b) => a + b, 0)}
          </div>
          <div class="kpi-footer">
            <span>Across 20 mirrored schema tables</span>
          </div>
        </div>
      </div>

      <!-- Backups Table -->
      <div class="glass-panel">
        <div class="panel-header">
          <div>
            <h3 class="panel-title">Available Database Snapshots (${backups.length})</h3>
            <p class="panel-subtitle">Point-in-time SQLite disaster recovery files stored in backend/backups/</p>
          </div>
        </div>
        <div class="table-responsive">
          <table class="admin-table">
            <thead>
              <tr>
                <th>Backup Filename</th>
                <th>Snapshot Timestamp</th>
                <th>File Size</th>
                <th style="text-align: right;">Download Action</th>
              </tr>
            </thead>
            <tbody>
              ${backups.length ? backups.map((b) => `
                <tr>
                  <td><strong style="color: #FFF;">${b.filename}</strong></td>
                  <td>${new Date(b.createdAt).toLocaleString('en-IN')}</td>
                  <td>${b.sizeFormatted}</td>
                  <td style="text-align: right;">
                    <a href="/api/v1/admin/backups/${b.filename}" class="btn btn-sm btn-secondary" target="_blank" download>
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
                      <span>Download .db</span>
                    </a>
                  </td>
                </tr>
              `).join('') : '<tr><td colspan="4" style="text-align: center; color: var(--text-muted);">No backups created yet</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;

    document.getElementById('btn-create-backup-view')?.addEventListener('click', async () => {
      const btn = document.getElementById('btn-create-backup-view');
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> Snapshotting...';
      try {
        const snap = await api('/api/v1/admin/backups', { method: 'POST' });
        showToast(`Snapshot created: ${snap.filename} (${snap.sizeFormatted})`);
        renderHealthView();
      } catch (err) {
        showToast(err.message, 'error');
        btn.disabled = false;
        btn.innerHTML = '<span>Trigger Atomic SQLite Backup</span>';
      }
    });
  } catch (err) {
    mount.innerHTML = `<div class="auth-error-banner">Failed to load health telemetry: ${err.message}</div>`;
  }
}

// --- VIEW 6: AUDIT TRAIL ---
async function renderAuditView() {
  const mount = document.getElementById('view-mount-point');
  try {
    const logs = await api('/api/v1/admin/audit-logs?limit=100');

    mount.innerHTML = `
      <div class="view-header">
        <div class="view-title-group">
          <h1>System Audit Trail & Compliance Log</h1>
          <p>Chronological record of administrative operations, license changes, and data mutations</p>
        </div>
      </div>

      <div class="glass-panel">
        <div class="panel-header">
          <div>
            <h3 class="panel-title">Audit Events Stream (${logs.length})</h3>
            <p class="panel-subtitle">Tamper-evident system activity</p>
          </div>
        </div>
        <div class="table-responsive">
          <table class="admin-table">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Entity & Target</th>
                <th>Business</th>
                <th>Changes</th>
              </tr>
            </thead>
            <tbody>
              ${logs.length ? logs.map((l) => `
                <tr>
                  <td>${new Date(l.createdAt).toLocaleString('en-IN')}</td>
                  <td>
                    <span class="table-entity-title">${l.actor?.name || 'System Auto'}</span>
                    <span class="table-entity-sub">${l.actor?.email || 'daemon'}</span>
                  </td>
                  <td><span class="status-badge status-active">${l.action}</span></td>
                  <td>${l.entity} (${l.entityId || '--'})</td>
                  <td>${l.business?.name || 'Global'}</td>
                  <td>
                    <code style="font-size: 0.72rem; max-width: 320px; display: inline-block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                      ${l.after || l.before || 'No diff'}
                    </code>
                  </td>
                </tr>
              `).join('') : '<tr><td colspan="6" style="text-align: center; color: var(--text-muted);">No audit logs recorded</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    `;
  } catch (err) {
    mount.innerHTML = `<div class="auth-error-banner">Failed to load audit logs: ${err.message}</div>`;
  }
}

// ==========================================
// Modals Handling
// ==========================================
function openSubscriptionModal(business) {
  const modalContainer = document.getElementById('modal-container');
  const subModal = document.getElementById('modal-edit-subscription');
  const inspectModal = document.getElementById('modal-inspect-sync');

  inspectModal.style.display = 'none';
  subModal.style.display = 'block';
  modalContainer.classList.add('active');

  document.getElementById('sub-modal-business-id').value = business.id;
  document.getElementById('sub-modal-business-name').textContent = business.name;
  document.getElementById('sub-modal-tier').value = business.subscriptionTier || 'pro';
  document.getElementById('sub-modal-status').value = business.subscriptionStatus || 'active';
  document.getElementById('sub-modal-devices').value = business.maxDevices || 5;

  if (business.subscriptionExpiresAt) {
    document.getElementById('sub-modal-expiry').value = business.subscriptionExpiresAt.split('T')[0];
  } else {
    document.getElementById('sub-modal-expiry').value = '';
  }

  const closeBtn = document.getElementById('btn-close-sub-modal');
  const cancelBtn = document.getElementById('btn-cancel-sub-modal');
  const closeModal = () => {
    modalContainer.classList.remove('active');
    subModal.style.display = 'none';
  };

  closeBtn.onclick = closeModal;
  cancelBtn.onclick = closeModal;

  const form = document.getElementById('form-edit-subscription');
  form.onsubmit = async (e) => {
    e.preventDefault();
    const id = document.getElementById('sub-modal-business-id').value;
    const tier = document.getElementById('sub-modal-tier').value;
    const status = document.getElementById('sub-modal-status').value;
    const maxDevices = parseInt(document.getElementById('sub-modal-devices').value, 10);
    const expiry = document.getElementById('sub-modal-expiry').value;

    const payload = {
      tier,
      status,
      maxDevices,
      expiresAt: expiry ? new Date(expiry).toISOString() : null,
    };

    const saveBtn = document.getElementById('btn-save-sub-modal');
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving...';

    try {
      await api(`/api/v1/admin/businesses/${id}/subscription`, {
        method: 'PATCH',
        body: JSON.stringify(payload),
      });

      showToast(`Subscription updated for ${business.name}!`);
      closeModal();
      loadCurrentView();
    } catch (err) {
      showToast(err.message, 'error');
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save License Settings';
    }
  };
}

function openInspectModal(item) {
  const modalContainer = document.getElementById('modal-container');
  const subModal = document.getElementById('modal-edit-subscription');
  const inspectModal = document.getElementById('modal-inspect-sync');

  subModal.style.display = 'none';
  inspectModal.style.display = 'block';
  modalContainer.classList.add('active');

  document.getElementById('inspect-sync-title').textContent = `${item.entity} #${item.entityId} (${item.op.toUpperCase()})`;

  let formatted = item.payload;
  try {
    formatted = JSON.stringify(JSON.parse(item.payload), null, 2);
  } catch {}

  document.getElementById('inspect-sync-payload').textContent = formatted || 'Empty payload';

  const errWrap = document.getElementById('inspect-sync-error-wrapper');
  const errEl = document.getElementById('inspect-sync-error');
  if (item.lastError) {
    errWrap.style.display = 'block';
    errEl.textContent = item.lastError;
  } else {
    errWrap.style.display = 'none';
  }

  const closeModal = () => {
    modalContainer.classList.remove('active');
    inspectModal.style.display = 'none';
  };

  document.getElementById('btn-close-inspect-modal').onclick = closeModal;
  document.getElementById('btn-close-inspect-action').onclick = closeModal;

  document.getElementById('btn-copy-sync-payload').onclick = () => {
    navigator.clipboard.writeText(formatted || '');
    showToast('Payload copied to clipboard');
  };

  document.getElementById('btn-retry-inspected-sync').onclick = async () => {
    try {
      await api(`/api/v1/admin/sync/retry/${item.id}`, { method: 'POST' });
      showToast('Sync item retry initiated successfully');
      closeModal();
      if (state.activeView === 'sync') renderSyncView();
    } catch (err) {
      showToast(err.message, 'error');
    }
  };
}

// ==========================================
// Application Bootstrap
// ==========================================
document.addEventListener('DOMContentLoaded', () => {
  initAuth();
  initRouter();
});
