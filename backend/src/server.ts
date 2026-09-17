import Fastify from 'fastify';
import { z } from 'zod';
import { config } from './config.js';
import { verifyAccessToken } from './lib/jwt.js';
import { registerUser, loginUser } from './services/auth.js';
import { calculateInvoiceTotals } from './services/ledger.js';
import { enqueueSync, pullSyncChanges } from './services/sync.js';
import { prisma } from './services/db.js';

export const app = Fastify({ logger: config.nodeEnv !== 'production' });

const authRegisterSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  password: z.string().min(6),
});

const authLoginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
});

const businessSchema = z.object({
  name: z.string().min(2),
  ownerName: z.string().optional(),
  gstin: z.string().optional(),
  city: z.string().optional(),
  state: z.string().optional(),
  currency: z.string().default('INR'),
});

const customerSchema = z.object({
  businessId: z.string(),
  name: z.string().min(2),
  phone: z.string().optional(),
  whatsapp: z.string().optional(),
  email: z.string().optional(),
  gstin: z.string().optional(),
  billingAddress: z.string().optional(),
  shippingAddress: z.string().optional(),
  city: z.string().optional(),
  state: z.string().optional(),
  openingBalance: z.number().default(0),
  creditLimit: z.number().default(0),
  customerType: z.string().default('Retail'),
  notes: z.string().optional(),
});

const supplierSchema = z.object({
  businessId: z.string(),
  name: z.string().min(2),
  phone: z.string().optional(),
  whatsapp: z.string().optional(),
  email: z.string().optional(),
  address: z.string().optional(),
  gstin: z.string().optional(),
  pan: z.string().optional(),
  state: z.string().optional(),
  openingBalance: z.number().default(0),
  creditPeriod: z.number().default(0),
  notes: z.string().optional(),
});

const productSchema = z.object({
  businessId: z.string(),
  name: z.string().min(2),
  sku: z.string().optional(),
  itemCode: z.string().optional(),
  category: z.string().optional(),
  brand: z.string().optional(),
  hsn: z.string().optional(),
  barcode: z.string().optional(),
  unit: z.string().default('pc'),
  gstRate: z.number().default(0),
  purchasePrice: z.number().default(0),
  salePrice: z.number().default(0),
  stock: z.number().default(0),
  costAverage: z.number().default(0),
  lowStockThreshold: z.number().default(5),
  description: z.string().optional(),
});

const invoiceItemSchema = z.object({
  productId: z.string().optional(),
  name: z.string(),
  hsn: z.string().optional(),
  quantity: z.number().default(1),
  price: z.number().default(0),
  gstRate: z.number().default(0),
  discount: z.number().default(0),
});

const invoiceSchema = z.object({
  businessId: z.string(),
  number: z.string().min(1),
  customerId: z.string().optional(),
  customerName: z.string().min(1),
  date: z.string(),
  dueDate: z.string().optional(),
  gstType: z.string().default('gst'),
  paymentMode: z.string().default('Cash'),
  notes: z.string().optional(),
  items: z.array(invoiceItemSchema).default([]),
});

const quotationItemSchema = z.object({
  productId: z.string().optional(),
  name: z.string(),
  hsn: z.string().optional(),
  quantity: z.number().default(1),
  price: z.number().default(0),
  discount: z.number().default(0),
  taxable: z.number().default(0),
  tax: z.number().default(0),
  gstRate: z.number().default(0),
});

const quotationSchema = z.object({
  businessId: z.string(),
  number: z.string().min(1),
  customerId: z.string().optional(),
  customerName: z.string().optional(),
  date: z.string(),
  expiryDate: z.string().optional(),
  subtotal: z.number().default(0),
  discount: z.number().default(0),
  taxable: z.number().default(0),
  cgst: z.number().default(0),
  sgst: z.number().default(0),
  igst: z.number().default(0),
  total: z.number().default(0),
  notes: z.string().optional(),
  items: z.array(quotationItemSchema).default([]),
});

const orderItemSchema = z.object({
  productId: z.string().optional(),
  name: z.string(),
  quantity: z.number().default(1),
  price: z.number().default(0),
});

const salesOrderSchema = z.object({
  businessId: z.string(),
  number: z.string().min(1),
  customerId: z.string().optional(),
  customerName: z.string().optional(),
  date: z.string(),
  dueDate: z.string().optional(),
  total: z.number().default(0),
  notes: z.string().optional(),
  items: z.array(orderItemSchema).default([]),
});

const purchaseOrderSchema = z.object({
  businessId: z.string(),
  number: z.string().min(1),
  supplierId: z.string().optional(),
  supplierName: z.string().optional(),
  date: z.string(),
  expectedDate: z.string().optional(),
  total: z.number().default(0),
  notes: z.string().optional(),
  items: z.array(orderItemSchema).default([]),
});

const challanItemSchema = z.object({
  productId: z.string().optional(),
  name: z.string(),
  quantity: z.number().default(1),
});

const deliveryChallanSchema = z.object({
  businessId: z.string(),
  number: z.string().min(1),
  customerId: z.string().optional(),
  customerName: z.string().optional(),
  date: z.string(),
  address: z.string().optional(),
  transportDetails: z.string().optional(),
  items: z.array(challanItemSchema).default([]),
});

const returnItemSchema = z.object({
  productId: z.string().optional(),
  name: z.string(),
  hsn: z.string().optional(),
  quantity: z.number().default(1),
  price: z.number().default(0),
  taxable: z.number().default(0),
  tax: z.number().default(0),
  gstRate: z.number().default(0),
});

const returnSchema = z.object({
  businessId: z.string(),
  number: z.string().min(1),
  invoiceId: z.string().optional(),
  partyId: z.string().optional(),
  partyName: z.string().optional(),
  partyType: z.string().default('customer'),
  date: z.string(),
  subtotal: z.number().default(0),
  taxable: z.number().default(0),
  tax: z.number().default(0),
  total: z.number().default(0),
  reason: z.string().optional(),
  items: z.array(returnItemSchema).default([]),
});

const paymentSchema = z.object({
  businessId: z.string(),
  partyType: z.string().default('customer'),
  partyId: z.string().optional(),
  partyName: z.string().optional(),
  invoiceId: z.string().optional(),
  invoiceNumber: z.string().optional(),
  amount: z.number().default(0),
  mode: z.string().default('Cash'),
  date: z.string(),
  reference: z.string().optional(),
  type: z.string().default('in'),
  notes: z.string().optional(),
});

const expenseSchema = z.object({
  businessId: z.string(),
  category: z.string().min(1),
  amount: z.number().default(0),
  mode: z.string().default('Cash'),
  date: z.string(),
  description: z.string().optional(),
  vendor: z.string().optional(),
});

const bankAccountSchema = z.object({
  businessId: z.string(),
  bankName: z.string().min(1),
  accountName: z.string().optional(),
  accountNumber: z.string().optional(),
  openingBalance: z.number().default(0),
});

const chequeSchema = z.object({
  businessId: z.string(),
  chequeNumber: z.string().min(1),
  bankName: z.string().optional(),
  bankAccountId: z.string().optional(),
  partyType: z.string().optional(),
  partyId: z.string().optional(),
  partyName: z.string().optional(),
  amount: z.number().default(0),
  date: z.string(),
  clearingDate: z.string().optional(),
  type: z.string().default('in'),
  status: z.string().default('Pending'),
  notes: z.string().optional(),
});

app.get('/health', async () => ({ ok: true, service: 'pricepilot-bill-backend' }));

app.post('/api/v1/auth/register', async (request, reply) => {
  const parsed = authRegisterSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid registration payload' });
  }

  try {
    const result = await registerUser(parsed.data);
    return reply.code(201).send(result);
  } catch (error) {
    if (error instanceof Error && error.message === 'USER_EXISTS') {
      return reply.code(409).send({ error: 'User already exists' });
    }
    return reply.code(500).send({ error: 'Registration failed' });
  }
});

app.post('/api/v1/auth/login', async (request, reply) => {
  const parsed = authLoginSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid login payload' });
  }

  try {
    return await loginUser(parsed.data);
  } catch (error) {
    if (error instanceof Error && error.message === 'INVALID_CREDENTIALS') {
      return reply.code(401).send({ error: 'Invalid credentials' });
    }
    return reply.code(500).send({ error: 'Login failed' });
  }
});

app.addHook('preHandler', async (request, reply) => {
  const authHeader = request.headers.authorization;
  const isPublicRoute = request.url === '/health' || request.url.startsWith('/api/v1/auth/');

  if (isPublicRoute) return;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return reply.code(401).send({ error: 'Missing bearer token' });
  }
  try {
    const token = authHeader.replace('Bearer ', '');
    const payload = verifyAccessToken(token);
    (request as any).user = payload;
  } catch {
    return reply.code(401).send({ error: 'Invalid token' });
  }
});

// Businesses
app.get('/api/v1/businesses', async (request) => {
  const user = (request as any).user;
  return await prisma.business.findMany({
    where: { ownerId: user.sub },
  });
});

app.post('/api/v1/businesses', async (request, reply) => {
  const parsed = businessSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid business payload' });
  }

  const user = (request as any).user;
  const business = await prisma.business.create({
    data: {
      ...parsed.data,
      ownerId: user.sub,
    },
  });
  return reply.code(201).send(business);
});

// Customers
app.get('/api/v1/customers', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.customer.findMany({
    where: { businessId },
  });
});

app.post('/api/v1/customers', async (request, reply) => {
  const parsed = customerSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid customer payload' });
  }

  const customer = await prisma.customer.create({
    data: parsed.data,
  });
  return reply.code(201).send(customer);
});

// Suppliers
app.get('/api/v1/suppliers', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.supplier.findMany({
    where: { businessId },
  });
});

app.post('/api/v1/suppliers', async (request, reply) => {
  const parsed = supplierSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid supplier payload' });
  }

  const supplier = await prisma.supplier.create({
    data: parsed.data,
  });
  return reply.code(201).send(supplier);
});

// Products
app.get('/api/v1/products', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.product.findMany({
    where: { businessId },
  });
});

app.post('/api/v1/products', async (request, reply) => {
  const parsed = productSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid product payload' });
  }

  const product = await prisma.product.create({
    data: parsed.data,
  });
  return reply.code(201).send(product);
});

// Invoices
app.get('/api/v1/invoices', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.invoice.findMany({
    where: { businessId },
    include: { items: true },
  });
});

app.post('/api/v1/invoices', async (request, reply) => {
  const parsed = invoiceSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid invoice payload' });
  }

  const totals = calculateInvoiceTotals(parsed.data.items);

  const invoice = await prisma.invoice.create({
    data: {
      businessId: parsed.data.businessId,
      number: parsed.data.number,
      customerId: parsed.data.customerId,
      customerName: parsed.data.customerName,
      date: new Date(parsed.data.date),
      dueDate: parsed.data.dueDate ? new Date(parsed.data.dueDate) : undefined,
      subtotal: totals.subtotal,
      discount: totals.discount,
      tax: totals.tax,
      total: totals.total,
      status: 'Finalized',
      items: {
        create: parsed.data.items.map((item) => {
          const lineTotal = item.quantity * item.price;
          const taxable = Math.max(lineTotal - item.discount, 0);
          const tax = (taxable * item.gstRate) / 100;
          return {
            productId: item.productId,
            name: item.name,
            hsn: item.hsn,
            quantity: item.quantity,
            price: item.price,
            gstRate: item.gstRate,
            discount: item.discount,
            taxable,
            tax,
          };
        }),
      },
    },
    include: { items: true },
  });

  return reply.code(201).send(invoice);
});

// Quotations
app.get('/api/v1/quotations', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.quotation.findMany({
    where: { businessId },
    include: { items: true },
  });
});

app.post('/api/v1/quotations', async (request, reply) => {
  const parsed = quotationSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid quotation payload' });
  }

  const quotation = await prisma.quotation.create({
    data: {
      businessId: parsed.data.businessId,
      number: parsed.data.number,
      customerId: parsed.data.customerId,
      customerName: parsed.data.customerName,
      date: new Date(parsed.data.date),
      expiryDate: parsed.data.expiryDate ? new Date(parsed.data.expiryDate) : undefined,
      subtotal: parsed.data.subtotal,
      discount: parsed.data.discount,
      taxable: parsed.data.taxable,
      cgst: parsed.data.cgst,
      sgst: parsed.data.sgst,
      igst: parsed.data.igst,
      total: parsed.data.total,
      notes: parsed.data.notes,
      items: {
        create: parsed.data.items.map((it) => ({
          productId: it.productId,
          name: it.name,
          hsn: it.hsn,
          gstRate: it.gstRate,
          quantity: it.quantity,
          price: it.price,
          discount: it.discount,
          taxable: it.taxable,
          tax: it.tax,
        })),
      },
    },
    include: { items: true },
  });

  return reply.code(201).send(quotation);
});

// Sales Orders
app.get('/api/v1/orders', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.salesOrder.findMany({
    where: { businessId },
    include: { items: true },
  });
});

app.post('/api/v1/orders', async (request, reply) => {
  const parsed = salesOrderSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid sales order payload' });
  }

  const order = await prisma.salesOrder.create({
    data: {
      businessId: parsed.data.businessId,
      number: parsed.data.number,
      customerId: parsed.data.customerId,
      customerName: parsed.data.customerName,
      date: new Date(parsed.data.date),
      dueDate: parsed.data.dueDate ? new Date(parsed.data.dueDate) : undefined,
      total: parsed.data.total,
      notes: parsed.data.notes,
      items: {
        create: parsed.data.items.map((it) => ({
          productId: it.productId,
          name: it.name,
          quantity: it.quantity,
          price: it.price,
        })),
      },
    },
    include: { items: true },
  });

  return reply.code(201).send(order);
});

// Purchase Orders
app.get('/api/v1/purchase-orders', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.purchaseOrder.findMany({
    where: { businessId },
    include: { items: true },
  });
});

app.post('/api/v1/purchase-orders', async (request, reply) => {
  const parsed = purchaseOrderSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid purchase order payload' });
  }

  const po = await prisma.purchaseOrder.create({
    data: {
      businessId: parsed.data.businessId,
      number: parsed.data.number,
      supplierId: parsed.data.supplierId,
      supplierName: parsed.data.supplierName,
      date: new Date(parsed.data.date),
      expectedDate: parsed.data.expectedDate ? new Date(parsed.data.expectedDate) : undefined,
      total: parsed.data.total,
      notes: parsed.data.notes,
      items: {
        create: parsed.data.items.map((it) => ({
          productId: it.productId,
          name: it.name,
          quantity: it.quantity,
          price: it.price,
        })),
      },
    },
    include: { items: true },
  });

  return reply.code(201).send(po);
});

// Delivery Challans
app.get('/api/v1/challans', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.deliveryChallan.findMany({
    where: { businessId },
    include: { items: true },
  });
});

app.post('/api/v1/challans', async (request, reply) => {
  const parsed = deliveryChallanSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid delivery challan payload' });
  }

  const challan = await prisma.deliveryChallan.create({
    data: {
      businessId: parsed.data.businessId,
      number: parsed.data.number,
      customerId: parsed.data.customerId,
      customerName: parsed.data.customerName,
      date: new Date(parsed.data.date),
      address: parsed.data.address,
      transportDetails: parsed.data.transportDetails,
      items: {
        create: parsed.data.items.map((it) => ({
          productId: it.productId,
          name: it.name,
          quantity: it.quantity,
        })),
      },
    },
    include: { items: true },
  });

  return reply.code(201).send(challan);
});

// Returns
app.get('/api/v1/returns', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.return.findMany({
    where: { businessId },
    include: { items: true },
  });
});

app.post('/api/v1/returns', async (request, reply) => {
  const parsed = returnSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid return payload' });
  }

  const ret = await prisma.return.create({
    data: {
      businessId: parsed.data.businessId,
      number: parsed.data.number,
      invoiceId: parsed.data.invoiceId,
      partyId: parsed.data.partyId,
      partyName: parsed.data.partyName,
      partyType: parsed.data.partyType,
      date: new Date(parsed.data.date),
      subtotal: parsed.data.subtotal,
      taxable: parsed.data.taxable,
      tax: parsed.data.tax,
      total: parsed.data.total,
      reason: parsed.data.reason,
      items: {
        create: parsed.data.items.map((it) => ({
          productId: it.productId,
          name: it.name,
          hsn: it.hsn,
          gstRate: it.gstRate,
          quantity: it.quantity,
          price: it.price,
          taxable: it.taxable,
          tax: it.tax,
        })),
      },
    },
    include: { items: true },
  });

  return reply.code(201).send(ret);
});

// Payments
app.get('/api/v1/payments', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.payment.findMany({
    where: { businessId },
  });
});

app.post('/api/v1/payments', async (request, reply) => {
  const parsed = paymentSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid payment payload' });
  }

  const payment = await prisma.payment.create({
    data: {
      ...parsed.data,
      date: new Date(parsed.data.date),
    },
  });
  return reply.code(201).send(payment);
});

// Expenses
app.get('/api/v1/expenses', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.expense.findMany({
    where: { businessId },
  });
});

app.post('/api/v1/expenses', async (request, reply) => {
  const parsed = expenseSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid expense payload' });
  }

  const expense = await prisma.expense.create({
    data: {
      ...parsed.data,
      date: new Date(parsed.data.date),
    },
  });
  return reply.code(201).send(expense);
});

// Bank Accounts
app.get('/api/v1/bank-accounts', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.bankAccount.findMany({
    where: { businessId },
  });
});

app.post('/api/v1/bank-accounts', async (request, reply) => {
  const parsed = bankAccountSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid bank account payload' });
  }

  const account = await prisma.bankAccount.create({
    data: parsed.data,
  });
  return reply.code(201).send(account);
});

// Cheques
app.get('/api/v1/cheques', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.cheque.findMany({
    where: { businessId },
  });
});

app.post('/api/v1/cheques', async (request, reply) => {
  const parsed = chequeSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid cheque payload' });
  }

  const cheque = await prisma.cheque.create({
    data: {
      ...parsed.data,
      date: new Date(parsed.data.date),
      clearingDate: parsed.data.clearingDate ? new Date(parsed.data.clearingDate) : undefined,
    },
  });
  return reply.code(201).send(cheque);
});

// Ledger
app.get('/api/v1/ledger', async (request) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) return [];
  return await prisma.ledgerEntry.findMany({
    where: { businessId },
    orderBy: { date: 'asc' },
  });
});

// Sync Push (Batch or Single)
app.post('/api/v1/sync/push', async (request, reply) => {
  const queueItemSchema = z.object({
    businessId: z.string(),
    entity: z.string(),
    entityId: z.string(),
    op: z.enum(['upsert', 'delete', 'create']).default('upsert'),
    payload: z.string().optional().nullable(),
    idempotencyKey: z.string().optional().nullable(),
  });

  const parsed = queueItemSchema.safeParse(request.body);

  if (!parsed.success) {
    return reply.code(400).send({ error: 'Invalid sync payload', details: parsed.error.issues });
  }

  const record = await enqueueSync({
    businessId: parsed.data.businessId,
    entity: parsed.data.entity,
    entityId: parsed.data.entityId,
    op: parsed.data.op,
    payload: parsed.data.payload ?? null,
    idempotencyKey: parsed.data.idempotencyKey ?? null,
  });

  return reply.code(202).send({ accepted: true, record });
});

// Sync Pull (Delta cursor)
app.get('/api/v1/sync/pull', async (request, reply) => {
  const businessId = String(request.headers['x-business-id'] ?? (request.query as any)?.businessId ?? '');
  if (!businessId) {
    return reply.code(400).send({ error: 'Missing x-business-id header' });
  }

  const since = (request.query as any)?.since as string | undefined;
  const limit = Math.min(Number((request.query as any)?.limit ?? 100), 500);

  const result = await pullSyncChanges(businessId, since, limit);
  return reply.send(result);
});

const start = async () => {
  try {
    await app.listen({ port: config.port, host: '0.0.0.0' });
    app.log.info(`Server listening at http://localhost:${config.port}`);
  } catch (error) {
    app.log.error(error);
    process.exit(1);
  }
};

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  start();
}
