import fs from 'fs';
import path from 'path';
import { prisma } from './db.js';

export interface TenantBackupInfo {
  id: string;
  filename: string;
  sizeBytes: number;
  sizeFormatted: string;
  checksum?: string;
  deviceName?: string;
  notes?: string;
  createdAt: string;
}

const BACKUPS_BASE_DIR = path.resolve(process.cwd(), 'backups', 'tenants');

function ensureTenantDir(businessId: string): string {
  const dir = path.join(BACKUPS_BASE_DIR, businessId);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  return dir;
}

export async function uploadTenantBackup(params: {
  businessId: string;
  userId?: string;
  base64Data: string;
  filename?: string;
  checksum?: string;
  deviceName?: string;
  notes?: string;
}): Promise<TenantBackupInfo> {
  const { businessId, userId, base64Data, checksum, deviceName, notes } = params;
  const dir = ensureTenantDir(businessId);

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const safeFilename = params.filename || `backup_${timestamp}.enc`;
  const filePath = path.join(dir, safeFilename);

  const buffer = Buffer.from(base64Data, 'base64');
  fs.writeFileSync(filePath, buffer);

  const stat = fs.statSync(filePath);
  const info: TenantBackupInfo = {
    id: safeFilename,
    filename: safeFilename,
    sizeBytes: stat.size,
    sizeFormatted: `${(stat.size / 1024).toFixed(1)} KB`,
    checksum,
    deviceName,
    notes,
    createdAt: stat.birthtime.toISOString(),
  };

  // Write a metadata json alongside the file
  const metaPath = path.join(dir, `${safeFilename}.meta.json`);
  fs.writeFileSync(metaPath, JSON.stringify(info, null, 2));

  // Log in AuditLog if userId exists
  try {
    if (userId) {
      await prisma.auditLog.create({
        data: {
          action: 'CLOUD_BACKUP_CREATED',
          entity: 'database_backup',
          entityId: safeFilename,
          actorId: userId,
          businessId,
          after: JSON.stringify({
            filename: safeFilename,
            sizeBytes: stat.size,
            checksum,
            deviceName,
          }),
        },
      });
    }
  } catch {}

  return info;
}

export async function listTenantBackups(businessId: string): Promise<TenantBackupInfo[]> {
  const dir = ensureTenantDir(businessId);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.enc') || f.endsWith('.db') || f.endsWith('.bak'));

  const backups: TenantBackupInfo[] = [];

  for (const file of files) {
    const fullPath = path.join(dir, file);
    const metaPath = path.join(dir, `${file}.meta.json`);
    const stat = fs.statSync(fullPath);

    let meta: Partial<TenantBackupInfo> = {};
    if (fs.existsSync(metaPath)) {
      try {
        meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
      } catch {}
    }

    backups.push({
      id: file,
      filename: file,
      sizeBytes: stat.size,
      sizeFormatted: `${(stat.size / 1024).toFixed(1)} KB`,
      checksum: meta.checksum,
      deviceName: meta.deviceName,
      notes: meta.notes,
      createdAt: meta.createdAt || stat.birthtime.toISOString(),
    });
  }

  return backups.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
}

export async function getTenantBackup(businessId: string, backupId: string) {
  const dir = ensureTenantDir(businessId);
  const safeName = path.basename(backupId);
  const filePath = path.join(dir, safeName);

  if (!fs.existsSync(filePath)) {
    throw new Error(`Backup file ${safeName} not found`);
  }

  const stat = fs.statSync(filePath);
  const buffer = fs.readFileSync(filePath);

  return {
    id: safeName,
    filename: safeName,
    sizeBytes: stat.size,
    base64Data: buffer.toString('base64'),
    createdAt: stat.birthtime.toISOString(),
  };
}

export async function deleteTenantBackup(businessId: string, backupId: string) {
  const dir = ensureTenantDir(businessId);
  const safeName = path.basename(backupId);
  const filePath = path.join(dir, safeName);
  const metaPath = path.join(dir, `${safeName}.meta.json`);

  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }
  if (fs.existsSync(metaPath)) {
    fs.unlinkSync(metaPath);
  }
  return { ok: true, deleted: safeName };
}
