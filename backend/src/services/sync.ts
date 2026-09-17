import { prisma } from './db.js';

export async function enqueueSync(input: {
  businessId: string;
  entity: string;
  entityId: string;
  op: 'upsert' | 'delete' | 'create';
  payload?: string | null;
  idempotencyKey?: string | null;
}) {
  // Check if already enqueued with this idempotency key
  if (input.idempotencyKey) {
    const existing = await prisma.syncQueueItem.findUnique({
      where: { idempotencyKey: input.idempotencyKey },
    });
    if (existing) {
      return existing;
    }
  }

  const record = await prisma.syncQueueItem.create({
    data: {
      businessId: input.businessId,
      entity: input.entity,
      entityId: input.entityId,
      op: input.op,
      payload: input.payload ?? null,
      idempotencyKey: input.idempotencyKey ?? null,
      status: 'pending',
    },
  });

  // Attempt immediate materialization
  try {
    await processSyncItem(record.id);
  } catch (err) {
    // Log error and leave status as pending/failed for retry
    console.error(`Failed to materialize sync item ${record.id}:`, err);
  }

  return await prisma.syncQueueItem.findUnique({ where: { id: record.id } }) ?? record;
}

export async function processSyncItem(queueItemId: string): Promise<boolean> {
  const item = await prisma.syncQueueItem.findUnique({ where: { id: queueItemId } });
  if (!item) return false;

  try {
    let payload: Record<string, any> = {};
    if (item.payload) {
      try {
        payload = JSON.parse(item.payload);
      } catch {
        payload = { raw: item.payload };
      }
    }

    const { businessId, entity, op } = item;

    if (op === 'delete') {
      await handleDelete(entity, item.entityId, businessId);
    } else {
      await handleUpsert(entity, item.entityId, businessId, payload);
    }

    await prisma.syncQueueItem.update({
      where: { id: queueItemId },
      data: {
        status: 'synced',
        syncedAt: new Date(),
        lastError: null,
      },
    });
    return true;
  } catch (error: any) {
    await prisma.syncQueueItem.update({
      where: { id: queueItemId },
      data: {
        status: 'failed',
        attempts: item.attempts + 1,
        lastError: error?.message ?? String(error),
      },
    });
    throw error;
  }
}

async function handleDelete(entity: string, entityId: string, businessId: string) {
  switch (entity.toLowerCase()) {
    case 'customer':
    case 'customers':
      await prisma.customer.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'supplier':
    case 'suppliers':
      await prisma.supplier.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'product':
    case 'products':
      await prisma.product.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'invoice':
    case 'invoices':
      await prisma.invoice.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'payment':
    case 'payments':
      await prisma.payment.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'expense':
    case 'expenses':
      await prisma.expense.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'quotation':
    case 'quotations':
      await prisma.quotation.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'order':
    case 'orders':
    case 'sales_order':
    case 'sales_orders':
      await prisma.salesOrder.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'purchase_order':
    case 'purchase_orders':
      await prisma.purchaseOrder.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'delivery_challan':
    case 'delivery_challans':
      await prisma.deliveryChallan.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'bank_account':
    case 'bank_accounts':
      await prisma.bankAccount.deleteMany({ where: { id: entityId, businessId } });
      break;
    case 'cheque':
    case 'cheques':
      await prisma.cheque.deleteMany({ where: { id: entityId, businessId } });
      break;
  }
}

async function handleUpsert(entity: string, entityId: string, businessId: string, data: Record<string, any>) {
  switch (entity.toLowerCase()) {
    case 'customer':
    case 'customers': {
      const name = data.name ?? 'Unknown Customer';
      await prisma.customer.upsert({
        where: { id: entityId },
        create: {
          id: entityId,
          businessId,
          name,
          phone: data.phone ?? null,
          whatsapp: data.whatsapp ?? null,
          email: data.email ?? null,
          billingAddress: data.billing_address ?? data.billingAddress ?? null,
          shippingAddress: data.shipping_address ?? data.shippingAddress ?? null,
          gstin: data.gstin ?? null,
          pan: data.pan ?? null,
          state: data.state ?? null,
          city: data.city ?? null,
          pin: data.pin ?? data.pin_code ?? null,
          openingBalance: Number(data.opening_balance ?? data.openingBalance ?? 0),
          creditLimit: Number(data.credit_limit ?? data.creditLimit ?? 0),
          customerType: data.customer_type ?? data.customerType ?? 'Retail',
          notes: data.notes ?? null,
        },
        update: {
          name,
          phone: data.phone ?? undefined,
          whatsapp: data.whatsapp ?? undefined,
          email: data.email ?? undefined,
          billingAddress: data.billing_address ?? data.billingAddress ?? undefined,
          shippingAddress: data.shipping_address ?? data.shippingAddress ?? undefined,
          gstin: data.gstin ?? undefined,
          pan: data.pan ?? undefined,
          state: data.state ?? undefined,
          city: data.city ?? undefined,
          openingBalance: data.opening_balance !== undefined ? Number(data.opening_balance) : undefined,
        },
      });
      break;
    }

    case 'supplier':
    case 'suppliers': {
      const name = data.name ?? 'Unknown Supplier';
      await prisma.supplier.upsert({
        where: { id: entityId },
        create: {
          id: entityId,
          businessId,
          name,
          phone: data.phone ?? null,
          whatsapp: data.whatsapp ?? null,
          email: data.email ?? null,
          address: data.address ?? null,
          gstin: data.gstin ?? null,
          pan: data.pan ?? null,
          state: data.state ?? null,
          openingBalance: Number(data.opening_balance ?? data.openingBalance ?? 0),
          creditPeriod: Number(data.credit_period ?? data.creditPeriod ?? 0),
          notes: data.notes ?? null,
        },
        update: {
          name,
          phone: data.phone ?? undefined,
          whatsapp: data.whatsapp ?? undefined,
          email: data.email ?? undefined,
          address: data.address ?? undefined,
          gstin: data.gstin ?? undefined,
          pan: data.pan ?? undefined,
        },
      });
      break;
    }

    case 'product':
    case 'products': {
      const name = data.name ?? 'Item';
      await prisma.product.upsert({
        where: { id: entityId },
        create: {
          id: entityId,
          businessId,
          name,
          sku: data.sku ?? null,
          itemCode: data.item_code ?? data.itemCode ?? null,
          category: data.category ?? null,
          brand: data.brand ?? null,
          hsn: data.hsn ?? null,
          barcode: data.barcode ?? null,
          unit: data.unit ?? 'pc',
          gstRate: Number(data.gst_rate ?? data.gstRate ?? 0),
          purchasePrice: Number(data.purchase_price ?? data.purchasePrice ?? 0),
          salePrice: Number(data.sale_price ?? data.salePrice ?? 0),
          mrp: Number(data.mrp ?? 0),
          stock: Number(data.stock ?? 0),
          costAverage: Number(data.cost_average ?? data.costAverage ?? 0),
          lowStockThreshold: Number(data.low_stock_threshold ?? data.lowStockThreshold ?? 5),
          description: data.description ?? null,
        },
        update: {
          name,
          sku: data.sku ?? undefined,
          barcode: data.barcode ?? undefined,
          salePrice: data.sale_price !== undefined ? Number(data.sale_price) : undefined,
          purchasePrice: data.purchase_price !== undefined ? Number(data.purchase_price) : undefined,
          stock: data.stock !== undefined ? Number(data.stock) : undefined,
          costAverage: data.cost_average !== undefined ? Number(data.cost_average) : undefined,
        },
      });
      break;
    }

    case 'invoice':
    case 'invoices': {
      const number = String(data.number ?? entityId);
      const existing = await prisma.invoice.findFirst({
        where: { businessId, number },
      });
      const invoiceData = {
        businessId,
        number,
        customerId: data.customer_id ? String(data.customer_id) : (data.customerId ?? null),
        customerName: data.customer_name ?? data.customerName ?? 'Walk-in Customer',
        date: data.date ? new Date(data.date) : new Date(),
        dueDate: data.due_date ? new Date(data.due_date) : (data.dueDate ? new Date(data.dueDate) : null),
        gstType: data.gst_type ?? data.gstType ?? 'gst',
        subtotal: Number(data.subtotal ?? 0),
        discount: Number(data.discount ?? 0),
        taxable: Number(data.taxable ?? 0),
        cgst: Number(data.cgst ?? 0),
        sgst: Number(data.sgst ?? 0),
        igst: Number(data.igst ?? 0),
        roundOff: Number(data.round_off ?? data.roundOff ?? 0),
        total: Number(data.total ?? 0),
        amountPaid: Number(data.amount_paid ?? data.amountPaid ?? 0),
        paymentMode: data.payment_mode ?? data.paymentMode ?? 'Cash',
        status: data.status ?? 'Finalized',
        notes: data.notes ?? null,
      };

      if (existing) {
        await prisma.invoice.update({
          where: { id: existing.id },
          data: invoiceData,
        });
      } else {
        await prisma.invoice.create({
          data: {
            id: entityId,
            ...invoiceData,
          },
        });
      }
      break;
    }

    case 'payment':
    case 'payments': {
      await prisma.payment.upsert({
        where: { id: entityId },
        create: {
          id: entityId,
          businessId,
          partyType: data.party_type ?? data.partyType ?? 'customer',
          partyId: data.party_id ? String(data.party_id) : (data.partyId ?? null),
          partyName: data.party_name ?? data.partyName ?? null,
          invoiceId: data.invoice_id ? String(data.invoice_id) : (data.invoiceId ?? null),
          invoiceNumber: data.invoice_number ?? data.invoiceNumber ?? null,
          amount: Number(data.amount ?? 0),
          mode: data.mode ?? 'Cash',
          date: data.date ? new Date(data.date) : new Date(),
          reference: data.reference ?? null,
          type: data.type ?? 'in',
          notes: data.notes ?? null,
        },
        update: {
          amount: Number(data.amount ?? 0),
          mode: data.mode ?? undefined,
          date: data.date ? new Date(data.date) : undefined,
          notes: data.notes ?? undefined,
        },
      });
      break;
    }

    case 'expense':
    case 'expenses': {
      await prisma.expense.upsert({
        where: { id: entityId },
        create: {
          id: entityId,
          businessId,
          category: data.category ?? 'General',
          amount: Number(data.amount ?? 0),
          mode: data.mode ?? 'Cash',
          date: data.date ? new Date(data.date) : new Date(),
          description: data.description ?? null,
          vendor: data.vendor ?? null,
        },
        update: {
          category: data.category ?? undefined,
          amount: Number(data.amount ?? 0),
          mode: data.mode ?? undefined,
          description: data.description ?? undefined,
        },
      });
      break;
    }

    case 'bank_account':
    case 'bank_accounts': {
      await prisma.bankAccount.upsert({
        where: { id: entityId },
        create: {
          id: entityId,
          businessId,
          bankName: data.bank_name ?? data.bankName ?? 'Bank',
          accountName: data.account_name ?? data.accountName ?? null,
          accountNumber: data.account_number ?? data.accountNumber ?? null,
          openingBalance: Number(data.opening_balance ?? data.openingBalance ?? 0),
        },
        update: {
          bankName: data.bank_name ?? data.bankName ?? undefined,
          accountName: data.account_name ?? data.accountName ?? undefined,
          openingBalance: data.opening_balance !== undefined ? Number(data.opening_balance) : undefined,
        },
      });
      break;
    }

    case 'cheque':
    case 'cheques': {
      await prisma.cheque.upsert({
        where: { id: entityId },
        create: {
          id: entityId,
          businessId,
          chequeNumber: data.cheque_number ?? data.chequeNumber ?? 'CHQ',
          bankName: data.bank_name ?? data.bankName ?? null,
          bankAccountId: data.bank_account_id ? String(data.bank_account_id) : (data.bankAccountId ?? null),
          partyType: data.party_type ?? data.partyType ?? null,
          partyId: data.party_id ? String(data.party_id) : (data.partyId ?? null),
          partyName: data.party_name ?? data.partyName ?? null,
          amount: Number(data.amount ?? 0),
          date: data.date ? new Date(data.date) : new Date(),
          type: data.type ?? 'in',
          status: data.status ?? 'Pending',
          notes: data.notes ?? null,
        },
        update: {
          status: data.status ?? undefined,
          clearingDate: data.clearing_date ? new Date(data.clearing_date) : undefined,
          bounceReason: data.bounce_reason ?? data.bounceReason ?? undefined,
        },
      });
      break;
    }

    default:
      console.log(`Sync handler for entity '${entity}' not specifically mapped; stored in sync queue.`);
  }
}

export async function pullSyncChanges(businessId: string, since?: string, limit = 100) {
  const sinceDate = since ? new Date(since) : new Date(0);
  const changes: Array<{
    entity: string;
    entityId: string;
    op: string;
    payload: string;
    timestamp: string;
  }> = [];

  const [customers, products, invoices, payments, expenses, bankAccounts, cheques] = await Promise.all([
    prisma.customer.findMany({
      where: { businessId, createdAt: { gt: sinceDate } },
      take: limit,
      orderBy: { createdAt: 'asc' },
    }),
    prisma.product.findMany({
      where: { businessId, createdAt: { gt: sinceDate } },
      take: limit,
      orderBy: { createdAt: 'asc' },
    }),
    prisma.invoice.findMany({
      where: { businessId, createdAt: { gt: sinceDate } },
      include: { items: true },
      take: limit,
      orderBy: { createdAt: 'asc' },
    }),
    prisma.payment.findMany({
      where: { businessId, createdAt: { gt: sinceDate } },
      take: limit,
      orderBy: { createdAt: 'asc' },
    }),
    prisma.expense.findMany({
      where: { businessId, createdAt: { gt: sinceDate } },
      take: limit,
      orderBy: { createdAt: 'asc' },
    }),
    prisma.bankAccount.findMany({
      where: { businessId, createdAt: { gt: sinceDate } },
      take: limit,
      orderBy: { createdAt: 'asc' },
    }),
    prisma.cheque.findMany({
      where: { businessId, createdAt: { gt: sinceDate } },
      take: limit,
      orderBy: { createdAt: 'asc' },
    }),
  ]);

  for (const c of customers) {
    changes.push({
      entity: 'customer',
      entityId: c.id,
      op: 'upsert',
      payload: JSON.stringify(c),
      timestamp: c.createdAt.toISOString(),
    });
  }

  for (const p of products) {
    changes.push({
      entity: 'product',
      entityId: p.id,
      op: 'upsert',
      payload: JSON.stringify(p),
      timestamp: p.createdAt.toISOString(),
    });
  }

  for (const inv of invoices) {
    changes.push({
      entity: 'invoice',
      entityId: inv.id,
      op: 'upsert',
      payload: JSON.stringify(inv),
      timestamp: inv.createdAt.toISOString(),
    });
  }

  for (const pay of payments) {
    changes.push({
      entity: 'payment',
      entityId: pay.id,
      op: 'upsert',
      payload: JSON.stringify(pay),
      timestamp: pay.createdAt.toISOString(),
    });
  }

  for (const exp of expenses) {
    changes.push({
      entity: 'expense',
      entityId: exp.id,
      op: 'upsert',
      payload: JSON.stringify(exp),
      timestamp: exp.createdAt.toISOString(),
    });
  }

  for (const ba of bankAccounts) {
    changes.push({
      entity: 'bank_account',
      entityId: ba.id,
      op: 'upsert',
      payload: JSON.stringify(ba),
      timestamp: ba.createdAt.toISOString(),
    });
  }

  for (const chq of cheques) {
    changes.push({
      entity: 'cheque',
      entityId: chq.id,
      op: 'upsert',
      payload: JSON.stringify(chq),
      timestamp: chq.createdAt.toISOString(),
    });
  }

  // Sort chronologically
  changes.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

  return {
    changes: changes.slice(0, limit),
    serverTime: new Date().toISOString(),
  };
}
