import fs from 'fs';
import path from 'path';
import { prisma } from './db.js';
import { processSyncItem } from './sync.js';

export async function getAdminOverview() {
  const [
    businessCount,
    userCount,
    invoiceCount,
    revenueAgg,
    syncStats,
    recentAudit,
    tierBreakdown,
  ] = await Promise.all([
    prisma.business.count(),
    prisma.user.count(),
    prisma.invoice.count(),
    prisma.invoice.aggregate({
      _sum: { total: true },
    }),
    prisma.syncQueueItem.groupBy({
      by: ['status'],
      _count: { id: true },
    }),
    prisma.auditLog.findMany({
      take: 8,
      orderBy: { createdAt: 'desc' },
      include: {
        actor: { select: { id: true, name: true, email: true, role: true } },
        business: { select: { id: true, name: true } },
      },
    }),
    prisma.business.groupBy({
      by: ['subscriptionTier'],
      _count: { id: true },
    }),
  ]);

  const syncCounts = {
    pending: 0,
    synced: 0,
    failed: 0,
    total: 0,
  };

  for (const s of syncStats) {
    if (s.status === 'pending') syncCounts.pending += s._count.id;
    else if (s.status === 'synced') syncCounts.synced += s._count.id;
    else if (s.status === 'failed') syncCounts.failed += s._count.id;
    syncCounts.total += s._count.id;
  }

  return {
    totalBusinesses: businessCount,
    totalUsers: userCount,
    totalInvoices: invoiceCount,
    totalRevenueCents: revenueAgg._sum.total ?? 0,
    syncStats: syncCounts,
    tierBreakdown: tierBreakdown.map((t) => ({
      tier: t.subscriptionTier,
      count: t._count.id,
    })),
    recentAudit,
  };
}

export async function listAdminBusinesses(search?: string) {
  const where: any = {};
  if (search && search.trim()) {
    const q = search.trim();
    where.OR = [
      { name: { contains: q } },
      { ownerName: { contains: q } },
      { gstin: { contains: q } },
      { phone: { contains: q } },
      { email: { contains: q } },
    ];
  }

  const businesses = await prisma.business.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    include: {
      owner: { select: { id: true, name: true, email: true, role: true } },
      _count: {
        select: {
          invoices: true,
          customers: true,
          products: true,
          payments: true,
          syncQueue: true,
        },
      },
      invoices: {
        select: { total: true },
      },
      syncQueue: {
        take: 1,
        orderBy: { createdAt: 'desc' },
        select: { createdAt: true, status: true },
      },
    },
  });

  return businesses.map((b) => {
    const totalRevenueCents = b.invoices.reduce((acc, inv) => acc + inv.total, 0);
    const lastSync = b.syncQueue[0] ?? null;

    return {
      id: b.id,
      name: b.name,
      ownerName: b.ownerName,
      phone: b.phone,
      email: b.email,
      city: b.city,
      state: b.state,
      gstin: b.gstin,
      currency: b.currency,
      subscriptionTier: b.subscriptionTier,
      subscriptionStatus: b.subscriptionStatus,
      subscriptionExpiresAt: b.subscriptionExpiresAt,
      maxDevices: b.maxDevices,
      createdAt: b.createdAt,
      owner: b.owner,
      counts: b._count,
      totalRevenueCents,
      lastSyncAt: lastSync?.createdAt ?? null,
      lastSyncStatus: lastSync?.status ?? 'idle',
    };
  });
}

export async function getAdminBusinessDetail(businessId: string) {
  const business = await prisma.business.findUnique({
    where: { id: businessId },
    include: {
      owner: { select: { id: true, name: true, email: true, role: true } },
      invoices: {
        take: 10,
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          number: true,
          customerName: true,
          date: true,
          total: true,
          status: true,
        },
      },
      customers: {
        take: 10,
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          name: true,
          phone: true,
          customerType: true,
          openingBalance: true,
        },
      },
      products: {
        take: 10,
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          name: true,
          sku: true,
          stock: true,
          salePrice: true,
        },
      },
      _count: {
        select: {
          invoices: true,
          customers: true,
          products: true,
          suppliers: true,
          payments: true,
          expenses: true,
          cheques: true,
          syncQueue: true,
        },
      },
    },
  });

  return business;
}

export async function updateBusinessSubscription(
  businessId: string,
  data: {
    tier?: string;
    status?: string;
    expiresAt?: string | null;
    maxDevices?: number;
  },
  actorId?: string
) {
  const existing = await prisma.business.findUnique({ where: { id: businessId } });
  if (!existing) {
    throw new Error(`Business ${businessId} not found`);
  }

  const updated = await prisma.business.update({
    where: { id: businessId },
    data: {
      ...(data.tier ? { subscriptionTier: data.tier } : {}),
      ...(data.status ? { subscriptionStatus: data.status } : {}),
      ...(data.expiresAt !== undefined
        ? { subscriptionExpiresAt: data.expiresAt ? new Date(data.expiresAt) : null }
        : {}),
      ...(data.maxDevices !== undefined ? { maxDevices: data.maxDevices } : {}),
    },
  });

  // Log in AuditLog
  await prisma.auditLog.create({
    data: {
      businessId,
      actorId: actorId ?? null,
      action: 'UPDATE_SUBSCRIPTION',
      entity: 'Business',
      entityId: businessId,
      before: JSON.stringify({
        tier: existing.subscriptionTier,
        status: existing.subscriptionStatus,
        expiresAt: existing.subscriptionExpiresAt,
        maxDevices: existing.maxDevices,
      }),
      after: JSON.stringify({
        tier: updated.subscriptionTier,
        status: updated.subscriptionStatus,
        expiresAt: updated.subscriptionExpiresAt,
        maxDevices: updated.maxDevices,
      }),
    },
  });

  return updated;
}

export async function listAdminUsers() {
  const users = await prisma.user.findMany({
    orderBy: { createdAt: 'desc' },
    include: {
      businesses: {
        select: { id: true, name: true, subscriptionTier: true },
      },
      _count: {
        select: { businesses: true, auditLogs: true },
      },
    },
  });

  return users.map((u) => ({
    id: u.id,
    name: u.name,
    email: u.email,
    role: u.role,
    createdAt: u.createdAt,
    businesses: u.businesses,
    businessCount: u._count.businesses,
  }));
}

export async function updateUserRole(userId: string, role: string, actorId?: string) {
  const existing = await prisma.user.findUnique({ where: { id: userId } });
  if (!existing) {
    throw new Error(`User ${userId} not found`);
  }

  const updated = await prisma.user.update({
    where: { id: userId },
    data: { role },
  });

  await prisma.auditLog.create({
    data: {
      actorId: actorId ?? null,
      action: 'UPDATE_USER_ROLE',
      entity: 'User',
      entityId: userId,
      before: JSON.stringify({ role: existing.role }),
      after: JSON.stringify({ role: updated.role }),
    },
  });

  return { id: updated.id, name: updated.name, email: updated.email, role: updated.role };
}

export async function createDatabaseBackup(actorId?: string) {
  const dbDir = path.resolve(process.cwd(), 'prisma');
  const dbPath = path.join(dbDir, 'dev.db');
  const backupDir = path.resolve(process.cwd(), 'backups');

  if (!fs.existsSync(backupDir)) {
    fs.mkdirSync(backupDir, { recursive: true });
  }

  if (!fs.existsSync(dbPath)) {
    throw new Error(`Database file not found at ${dbPath}`);
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `backup-${timestamp}.db`;
  const targetPath = path.join(backupDir, filename);

  fs.copyFileSync(dbPath, targetPath);
  const stats = fs.statSync(targetPath);

  await prisma.auditLog.create({
    data: {
      actorId: actorId ?? null,
      action: 'CREATE_BACKUP',
      entity: 'Database',
      entityId: filename,
      after: JSON.stringify({
        filename,
        sizeBytes: stats.size,
        createdAt: new Date().toISOString(),
      }),
    },
  });

  return {
    filename,
    sizeBytes: stats.size,
    sizeFormatted: `${(stats.size / 1024).toFixed(1)} KB`,
    createdAt: stats.birthtime,
    path: targetPath,
  };
}

export async function listDatabaseBackups() {
  const backupDir = path.resolve(process.cwd(), 'backups');
  if (!fs.existsSync(backupDir)) {
    return [];
  }

  const files = fs.readdirSync(backupDir).filter((f) => f.endsWith('.db'));
  const backups = files.map((file) => {
    const fullPath = path.join(backupDir, file);
    const stat = fs.statSync(fullPath);
    return {
      filename: file,
      sizeBytes: stat.size,
      sizeFormatted: `${(stat.size / 1024).toFixed(1)} KB`,
      createdAt: stat.birthtime,
    };
  });

  return backups.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
}

export async function getSystemHealthTelemetry() {
  const dbPath = path.resolve(process.cwd(), 'prisma', 'dev.db');
  let dbSizeBytes = 0;
  try {
    if (fs.existsSync(dbPath)) {
      dbSizeBytes = fs.statSync(dbPath).size;
    }
  } catch {}

  const [
    businesses,
    users,
    customers,
    products,
    invoices,
    payments,
    expenses,
    syncQueueItems,
    auditLogs,
  ] = await Promise.all([
    prisma.business.count(),
    prisma.user.count(),
    prisma.customer.count(),
    prisma.product.count(),
    prisma.invoice.count(),
    prisma.payment.count(),
    prisma.expense.count(),
    prisma.syncQueueItem.count(),
    prisma.auditLog.count(),
  ]);

  const memory = process.memoryUsage();

  return {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptimeSeconds: Math.floor(process.uptime()),
    database: {
      type: 'SQLite (Prisma)',
      sizeBytes: dbSizeBytes,
      sizeFormatted: `${(dbSizeBytes / 1024).toFixed(1)} KB`,
      recordCounts: {
        businesses,
        users,
        customers,
        products,
        invoices,
        payments,
        expenses,
        syncQueueItems,
        auditLogs,
      },
    },
    system: {
      nodeVersion: process.version,
      platform: process.platform,
      arch: process.arch,
      memory: {
        rssMb: (memory.rss / (1024 * 1024)).toFixed(1),
        heapTotalMb: (memory.heapTotal / (1024 * 1024)).toFixed(1),
        heapUsedMb: (memory.heapUsed / (1024 * 1024)).toFixed(1),
      },
    },
  };
}

export async function getSyncQueueInspector(status?: string, limit = 100) {
  const where: any = {};
  if (status && status !== 'all') {
    where.status = status;
  }

  const items = await prisma.syncQueueItem.findMany({
    where,
    take: limit,
    orderBy: { createdAt: 'desc' },
    include: {
      business: { select: { id: true, name: true } },
    },
  });

  return items;
}

export async function retrySyncQueueItem(id: string) {
  const item = await prisma.syncQueueItem.findUnique({ where: { id } });
  if (!item) {
    throw new Error(`Sync queue item ${id} not found`);
  }

  // Reset status to pending
  await prisma.syncQueueItem.update({
    where: { id },
    data: {
      status: 'pending',
      attempts: item.attempts + 1,
      lastError: null,
    },
  });

  // Re-run materialization
  await processSyncItem(id);
  return await prisma.syncQueueItem.findUnique({ where: { id } });
}

export async function getAuditLogs(limit = 100, businessId?: string) {
  const where: any = {};
  if (businessId) {
    where.businessId = businessId;
  }

  const logs = await prisma.auditLog.findMany({
    where,
    take: limit,
    orderBy: { createdAt: 'desc' },
    include: {
      actor: { select: { id: true, name: true, email: true, role: true } },
      business: { select: { id: true, name: true } },
    },
  });

  return logs;
}
