import { prisma } from './db.js';
export async function enqueueSync(input) {
    // Check if already enqueued with this idempotency key
    if (input.idempotencyKey) {
        const existing = await prisma.syncQueueItem.findUnique({
            where: { idempotencyKey: input.idempotencyKey },
        });
        if (existing) {
            if (existing.status === 'failed') {
                try {
                    await processSyncItem(existing.id);
                }
                catch { }
            }
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
    }
    catch (err) {
        // Log error and leave status as pending/failed for retry
        console.error(`Failed to materialize sync item ${record.id}:`, err);
    }
    return await prisma.syncQueueItem.findUnique({ where: { id: record.id } }) ?? record;
}
export async function processSyncItem(queueItemId) {
    const item = await prisma.syncQueueItem.findUnique({ where: { id: queueItemId } });
    if (!item)
        return false;
    try {
        let payload = {};
        if (item.payload) {
            try {
                payload = JSON.parse(item.payload);
            }
            catch {
                payload = { raw: item.payload };
            }
        }
        const { businessId, entity, op } = item;
        if (op === 'delete') {
            await handleDelete(entity, item.entityId, businessId);
        }
        else {
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
    }
    catch (error) {
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
function toScopedId(businessId, entityId) {
    if (entityId.startsWith(`${businessId}_`))
        return entityId;
    return `${businessId}_${entityId}`;
}
function fromScopedId(businessId, id) {
    if (id.startsWith(`${businessId}_`)) {
        return id.substring(businessId.length + 1);
    }
    return id;
}
async function handleDelete(entity, entityId, businessId) {
    const scopedId = toScopedId(businessId, entityId);
    switch (entity.toLowerCase()) {
        case 'customer':
        case 'customers':
            await prisma.customer.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'supplier':
        case 'suppliers':
            await prisma.supplier.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'product':
        case 'products':
            await prisma.product.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'invoice':
        case 'invoices':
            await prisma.invoice.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'payment':
        case 'payments':
            await prisma.payment.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'expense':
        case 'expenses':
        case 'purchase':
        case 'purchases':
            await prisma.expense.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'quotation':
        case 'quotations':
            await prisma.quotation.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'order':
        case 'orders':
        case 'sales_order':
        case 'sales_orders':
            await prisma.salesOrder.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'purchase_order':
        case 'purchase_orders':
            await prisma.purchaseOrder.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'delivery_challan':
        case 'delivery_challans':
            await prisma.deliveryChallan.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'bank_account':
        case 'bank_accounts':
            await prisma.bankAccount.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'cheque':
        case 'cheques':
            await prisma.cheque.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
        case 'return':
        case 'returns':
            await prisma.return.deleteMany({
                where: { OR: [{ id: scopedId }, { id: entityId, businessId }] },
            });
            break;
    }
}
async function handleUpsert(entity, entityId, businessId, data) {
    const scopedId = toScopedId(businessId, entityId);
    switch (entity.toLowerCase()) {
        case 'customer':
        case 'customers': {
            const name = data.name ?? 'Unknown Customer';
            await prisma.customer.upsert({
                where: { id: scopedId },
                create: {
                    id: scopedId,
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
                    businessId,
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
                where: { id: scopedId },
                create: {
                    id: scopedId,
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
                    businessId,
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
                where: { id: scopedId },
                create: {
                    id: scopedId,
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
                    businessId,
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
            let verifiedCustomerId = null;
            const rawCustId = data.customer_id ? String(data.customer_id) : (data.customerId ? String(data.customerId) : null);
            if (rawCustId) {
                const scopedCustId = toScopedId(businessId, rawCustId);
                const cust = await prisma.customer.findFirst({
                    where: { OR: [{ id: scopedCustId }, { id: rawCustId, businessId }] },
                });
                if (cust) {
                    verifiedCustomerId = cust.id;
                }
            }
            const invoiceData = {
                businessId,
                number,
                customerId: verifiedCustomerId,
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
            const invId = existing ? existing.id : scopedId;
            if (existing) {
                await prisma.invoice.update({
                    where: { id: existing.id },
                    data: invoiceData,
                });
            }
            else {
                await prisma.invoice.create({
                    data: {
                        id: scopedId,
                        ...invoiceData,
                    },
                });
            }
            if (Array.isArray(data.items) && data.items.length > 0) {
                try {
                    await prisma.invoiceItem.deleteMany({ where: { invoiceId: invId } });
                    for (let idx = 0; idx < data.items.length; idx++) {
                        const it = data.items[idx];
                        const rawItemId = it.id ? String(it.id) : `item_${idx}_${Date.now()}`;
                        const scopedItemId = toScopedId(businessId, `${invId}_${rawItemId}`);
                        await prisma.invoiceItem.create({
                            data: {
                                id: scopedItemId,
                                invoiceId: invId,
                                name: it.name ?? 'Item',
                                hsn: it.hsn ?? null,
                                gstRate: Number(it.gstRate ?? it.gst_rate ?? 0),
                                quantity: Number(it.quantity ?? 1),
                                price: Number(it.price ?? 0),
                                discount: Number(it.discount ?? 0),
                                taxable: Number(it.taxable ?? 0),
                                tax: Number(it.tax ?? 0),
                                unit: it.unit ?? null,
                            },
                        });
                    }
                }
                catch (_) { }
            }
            break;
        }
        case 'payment':
        case 'payments': {
            await prisma.payment.upsert({
                where: { id: scopedId },
                create: {
                    id: scopedId,
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
                    businessId,
                    amount: Number(data.amount ?? 0),
                    mode: data.mode ?? undefined,
                    date: data.date ? new Date(data.date) : undefined,
                    notes: data.notes ?? undefined,
                },
            });
            break;
        }
        case 'expense':
        case 'expenses':
        case 'purchase':
        case 'purchases': {
            let desc = data.description ?? null;
            if (Array.isArray(data.items) && data.items.length > 0) {
                const itemJson = JSON.stringify(data.items);
                desc = desc ? `${desc}<!--ITEMS:${itemJson}-->` : `<!--ITEMS:${itemJson}-->`;
            }
            await prisma.expense.upsert({
                where: { id: scopedId },
                create: {
                    id: scopedId,
                    businessId,
                    category: data.category ?? (entity.toLowerCase().startsWith('purchase') ? 'Purchase' : 'General'),
                    amount: Number(data.amount ?? 0),
                    mode: data.mode ?? (entity.toLowerCase().startsWith('purchase') ? 'Credit' : 'Cash'),
                    date: data.date ? new Date(data.date) : new Date(),
                    description: desc,
                    vendor: data.vendor ?? null,
                },
                update: {
                    businessId,
                    category: data.category ?? undefined,
                    amount: Number(data.amount ?? 0),
                    mode: data.mode ?? undefined,
                    description: desc ?? undefined,
                },
            });
            break;
        }
        case 'bank_account':
        case 'bank_accounts': {
            await prisma.bankAccount.upsert({
                where: { id: scopedId },
                create: {
                    id: scopedId,
                    businessId,
                    bankName: data.bank_name ?? data.bankName ?? 'Bank',
                    accountName: data.account_name ?? data.accountName ?? null,
                    accountNumber: data.account_number ?? data.accountNumber ?? null,
                    openingBalance: Number(data.opening_balance ?? data.openingBalance ?? 0),
                },
                update: {
                    businessId,
                    bankName: data.bank_name ?? data.bankName ?? undefined,
                    accountName: data.account_name ?? data.accountName ?? undefined,
                    openingBalance: data.opening_balance !== undefined ? Number(data.opening_balance) : undefined,
                },
            });
            break;
        }
        case 'cheque':
        case 'cheques': {
            let verifiedBankAccountId = null;
            const rawBankId = data.bank_account_id ? String(data.bank_account_id) : (data.bankAccountId ? String(data.bankAccountId) : null);
            if (rawBankId) {
                const scopedBankId = toScopedId(businessId, rawBankId);
                const bank = await prisma.bankAccount.findFirst({
                    where: { OR: [{ id: scopedBankId }, { id: rawBankId, businessId }] },
                });
                if (bank) {
                    verifiedBankAccountId = bank.id;
                }
            }
            await prisma.cheque.upsert({
                where: { id: scopedId },
                create: {
                    id: scopedId,
                    businessId,
                    chequeNumber: data.cheque_number ?? data.chequeNumber ?? 'CHQ',
                    bankName: data.bank_name ?? data.bankName ?? null,
                    bankAccountId: verifiedBankAccountId,
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
                    businessId,
                    status: data.status ?? undefined,
                    clearingDate: data.clearing_date ? new Date(data.clearing_date) : undefined,
                    bounceReason: data.bounce_reason ?? data.bounceReason ?? undefined,
                },
            });
            break;
        }
        case 'stock_move':
        case 'stock_moves': {
            const rawProdId = String(data.product_id ?? data.productId ?? entityId);
            const scopedProdId = toScopedId(businessId, rawProdId);
            const changeQty = Number(data.change_qty ?? data.changeQty ?? 0);
            const qtyAfter = Number(data.qty_after ?? data.qtyAfter ?? 0);
            const moveType = String(data.move_type ?? data.moveType ?? 'adjustment');
            const refType = data.ref_type ?? data.refType ?? null;
            const refId = data.ref_id ? String(data.ref_id) : (data.refId ? String(data.refId) : null);
            const date = data.date ? new Date(data.date) : new Date();
            const product = await prisma.product.findFirst({
                where: { OR: [{ id: scopedProdId }, { id: rawProdId, businessId }] },
            });
            if (product) {
                await prisma.stockMove.create({
                    data: {
                        id: scopedId,
                        businessId,
                        productId: product.id,
                        changeQty,
                        qtyAfter,
                        moveType,
                        refType,
                        refId,
                        date,
                    },
                });
                await prisma.product.update({
                    where: { id: product.id },
                    data: { stock: { increment: changeQty } },
                });
            }
            break;
        }
        case 'quotation':
        case 'quotations': {
            const number = String(data.number ?? entityId);
            const existing = await prisma.quotation.findFirst({
                where: { businessId, number },
            });
            let verifiedCustomerId = null;
            const rawCustId = data.customer_id ? String(data.customer_id) : (data.customerId ? String(data.customerId) : null);
            if (rawCustId) {
                const scopedCustId = toScopedId(businessId, rawCustId);
                const cust = await prisma.customer.findFirst({
                    where: { OR: [{ id: scopedCustId }, { id: rawCustId, businessId }] },
                });
                if (cust)
                    verifiedCustomerId = cust.id;
            }
            const quotationData = {
                businessId,
                number,
                customerId: verifiedCustomerId,
                customerName: data.customer_name ?? data.customerName ?? null,
                date: data.date ? new Date(data.date) : new Date(),
                expiryDate: data.expiry_date ? new Date(data.expiry_date) : (data.expiryDate ? new Date(data.expiryDate) : null),
                gstType: data.gst_type ?? data.gstType ?? 'gst',
                subtotal: Number(data.subtotal ?? 0),
                discount: Number(data.discount ?? 0),
                taxable: Number(data.taxable ?? 0),
                cgst: Number(data.cgst ?? 0),
                sgst: Number(data.sgst ?? 0),
                igst: Number(data.igst ?? 0),
                total: Number(data.total ?? 0),
                status: data.status ?? 'Open',
                notes: data.notes ?? null,
                isProforma: Boolean(data.is_proforma ?? data.isProforma ?? false),
            };
            const qId = existing ? existing.id : scopedId;
            if (existing) {
                await prisma.quotation.update({ where: { id: existing.id }, data: quotationData });
            }
            else {
                await prisma.quotation.create({ data: { id: scopedId, ...quotationData } });
            }
            if (Array.isArray(data.items) && data.items.length > 0) {
                try {
                    await prisma.quotationItem.deleteMany({ where: { quotationId: qId } });
                    for (let idx = 0; idx < data.items.length; idx++) {
                        const it = data.items[idx];
                        const rawItemId = it.id ? String(it.id) : `qitem_${idx}_${Date.now()}`;
                        const scopedItemId = toScopedId(businessId, `${qId}_${rawItemId}`);
                        await prisma.quotationItem.create({
                            data: {
                                id: scopedItemId,
                                quotationId: qId,
                                name: it.name ?? 'Item',
                                hsn: it.hsn ?? null,
                                gstRate: Number(it.gst_rate ?? it.gstRate ?? 0),
                                quantity: Number(it.quantity ?? 1),
                                price: Number(it.price ?? 0),
                                discount: Number(it.discount ?? 0),
                                taxable: Number(it.taxable ?? 0),
                                tax: Number(it.tax ?? 0),
                            },
                        });
                    }
                }
                catch (_) { }
            }
            break;
        }
        case 'order':
        case 'orders':
        case 'sales_order':
        case 'sales_orders': {
            const number = String(data.number ?? entityId);
            const existing = await prisma.salesOrder.findFirst({
                where: { businessId, number },
            });
            let verifiedCustomerId = null;
            const rawCustId = data.customer_id ? String(data.customer_id) : (data.customerId ? String(data.customerId) : null);
            if (rawCustId) {
                const scopedCustId = toScopedId(businessId, rawCustId);
                const cust = await prisma.customer.findFirst({
                    where: { OR: [{ id: scopedCustId }, { id: rawCustId, businessId }] },
                });
                if (cust)
                    verifiedCustomerId = cust.id;
            }
            const orderData = {
                businessId,
                number,
                customerId: verifiedCustomerId,
                customerName: data.customer_name ?? data.customerName ?? null,
                date: data.date ? new Date(data.date) : new Date(),
                dueDate: data.due_date ? new Date(data.due_date) : (data.dueDate ? new Date(data.dueDate) : null),
                status: data.status ?? 'Pending',
                total: Number(data.total ?? 0),
                notes: data.notes ?? null,
            };
            const oId = existing ? existing.id : scopedId;
            if (existing) {
                await prisma.salesOrder.update({ where: { id: existing.id }, data: orderData });
            }
            else {
                await prisma.salesOrder.create({ data: { id: scopedId, ...orderData } });
            }
            if (Array.isArray(data.items) && data.items.length > 0) {
                try {
                    await prisma.salesOrderItem.deleteMany({ where: { orderId: oId } });
                    for (let idx = 0; idx < data.items.length; idx++) {
                        const it = data.items[idx];
                        const rawItemId = it.id ? String(it.id) : `soitem_${idx}_${Date.now()}`;
                        const scopedItemId = toScopedId(businessId, `${oId}_${rawItemId}`);
                        await prisma.salesOrderItem.create({
                            data: {
                                id: scopedItemId,
                                orderId: oId,
                                name: it.name ?? 'Item',
                                quantity: Number(it.quantity ?? 1),
                                price: Number(it.price ?? 0),
                            },
                        });
                    }
                }
                catch (_) { }
            }
            break;
        }
        case 'purchase_order':
        case 'purchase_orders': {
            const number = String(data.number ?? entityId);
            const existing = await prisma.purchaseOrder.findFirst({
                where: { businessId, number },
            });
            let verifiedSupplierId = null;
            const rawSuppId = data.supplier_id ? String(data.supplier_id) : (data.supplierId ? String(data.supplierId) : null);
            if (rawSuppId) {
                const scopedSuppId = toScopedId(businessId, rawSuppId);
                const supp = await prisma.supplier.findFirst({
                    where: { OR: [{ id: scopedSuppId }, { id: rawSuppId, businessId }] },
                });
                if (supp)
                    verifiedSupplierId = supp.id;
            }
            const poData = {
                businessId,
                number,
                supplierId: verifiedSupplierId,
                supplierName: data.supplier_name ?? data.supplierName ?? null,
                date: data.date ? new Date(data.date) : new Date(),
                expectedDate: data.expected_date ? new Date(data.expected_date) : (data.expectedDate ? new Date(data.expectedDate) : null),
                status: data.status ?? 'Draft',
                total: Number(data.total ?? 0),
                notes: data.notes ?? null,
            };
            const poId = existing ? existing.id : scopedId;
            if (existing) {
                await prisma.purchaseOrder.update({ where: { id: existing.id }, data: poData });
            }
            else {
                await prisma.purchaseOrder.create({ data: { id: scopedId, ...poData } });
            }
            if (Array.isArray(data.items) && data.items.length > 0) {
                try {
                    await prisma.purchaseOrderItem.deleteMany({ where: { orderId: poId } });
                    for (let idx = 0; idx < data.items.length; idx++) {
                        const it = data.items[idx];
                        const rawItemId = it.id ? String(it.id) : `poitem_${idx}_${Date.now()}`;
                        const scopedItemId = toScopedId(businessId, `${poId}_${rawItemId}`);
                        await prisma.purchaseOrderItem.create({
                            data: {
                                id: scopedItemId,
                                orderId: poId,
                                name: it.name ?? 'Item',
                                quantity: Number(it.quantity ?? 1),
                                price: Number(it.price ?? 0),
                            },
                        });
                    }
                }
                catch (_) { }
            }
            break;
        }
        case 'delivery_challan':
        case 'delivery_challans': {
            const number = String(data.number ?? entityId);
            const existing = await prisma.deliveryChallan.findFirst({
                where: { businessId, number },
            });
            let verifiedCustomerId = null;
            const rawCustId = data.customer_id ? String(data.customer_id) : (data.customerId ? String(data.customerId) : null);
            if (rawCustId) {
                const scopedCustId = toScopedId(businessId, rawCustId);
                const cust = await prisma.customer.findFirst({
                    where: { OR: [{ id: scopedCustId }, { id: rawCustId, businessId }] },
                });
                if (cust)
                    verifiedCustomerId = cust.id;
            }
            const dcData = {
                businessId,
                number,
                customerId: verifiedCustomerId,
                customerName: data.customer_name ?? data.customerName ?? null,
                date: data.date ? new Date(data.date) : new Date(),
                address: data.address ?? null,
                transportDetails: data.transport_details ?? data.transportDetails ?? null,
                status: data.status ?? 'Pending',
            };
            const dcId = existing ? existing.id : scopedId;
            if (existing) {
                await prisma.deliveryChallan.update({ where: { id: existing.id }, data: dcData });
            }
            else {
                await prisma.deliveryChallan.create({ data: { id: scopedId, ...dcData } });
            }
            if (Array.isArray(data.items) && data.items.length > 0) {
                try {
                    await prisma.deliveryChallanItem.deleteMany({ where: { challanId: dcId } });
                    for (let idx = 0; idx < data.items.length; idx++) {
                        const it = data.items[idx];
                        const rawItemId = it.id ? String(it.id) : `dcitem_${idx}_${Date.now()}`;
                        const scopedItemId = toScopedId(businessId, `${dcId}_${rawItemId}`);
                        await prisma.deliveryChallanItem.create({
                            data: {
                                id: scopedItemId,
                                challanId: dcId,
                                name: it.name ?? 'Item',
                                quantity: Number(it.quantity ?? 1),
                            },
                        });
                    }
                }
                catch (_) { }
            }
            break;
        }
        case 'return':
        case 'returns': {
            const number = String(data.number ?? entityId);
            const existing = await prisma.return.findFirst({
                where: { businessId, number },
            });
            const retData = {
                businessId,
                number,
                invoiceId: data.invoice_id ? String(data.invoice_id) : (data.invoiceId ? String(data.invoiceId) : null),
                partyId: data.party_id ? String(data.party_id) : (data.partyId ? String(data.partyId) : null),
                partyName: data.party_name ?? data.partyName ?? null,
                partyType: data.party_type ?? data.partyType ?? 'customer',
                date: data.date ? new Date(data.date) : new Date(),
                subtotal: Number(data.subtotal ?? 0),
                taxable: Number(data.taxable ?? 0),
                tax: Number(data.tax ?? 0),
                total: Number(data.total ?? 0),
                reason: data.reason ?? null,
                status: data.status ?? 'Finalized',
            };
            const retId = existing ? existing.id : scopedId;
            if (existing) {
                await prisma.return.update({ where: { id: existing.id }, data: retData });
            }
            else {
                await prisma.return.create({ data: { id: scopedId, ...retData } });
            }
            if (Array.isArray(data.items) && data.items.length > 0) {
                try {
                    await prisma.returnItem.deleteMany({ where: { returnId: retId } });
                    for (let idx = 0; idx < data.items.length; idx++) {
                        const it = data.items[idx];
                        const rawItemId = it.id ? String(it.id) : `retitem_${idx}_${Date.now()}`;
                        const scopedItemId = toScopedId(businessId, `${retId}_${rawItemId}`);
                        await prisma.returnItem.create({
                            data: {
                                id: scopedItemId,
                                returnId: retId,
                                name: it.name ?? 'Item',
                                hsn: it.hsn ?? null,
                                gstRate: Number(it.gst_rate ?? it.gstRate ?? 0),
                                quantity: Number(it.quantity ?? 1),
                                price: Number(it.price ?? 0),
                                taxable: Number(it.taxable ?? 0),
                                tax: Number(it.tax ?? 0),
                            },
                        });
                    }
                }
                catch (_) { }
            }
            break;
        }
        default:
            console.log(`Sync handler for entity '${entity}' not specifically mapped; stored in sync queue.`);
    }
}
export async function pullSyncChanges(businessId, since, limit = 100) {
    const sinceDate = since ? new Date(since) : new Date(0);
    const changes = [];
    const [customers, suppliers, products, invoices, quotations, salesOrders, purchaseOrders, deliveryChallans, returns, payments, expenses, bankAccounts, cheques, stockMoves, syncQueueItems,] = await Promise.all([
        prisma.customer.findMany({
            where: { businessId, createdAt: { gt: sinceDate } },
            take: limit,
            orderBy: { createdAt: 'asc' },
        }),
        prisma.supplier.findMany({
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
        prisma.quotation.findMany({
            where: { businessId, createdAt: { gt: sinceDate } },
            include: { items: true },
            take: limit,
            orderBy: { createdAt: 'asc' },
        }),
        prisma.salesOrder.findMany({
            where: { businessId, createdAt: { gt: sinceDate } },
            include: { items: true },
            take: limit,
            orderBy: { createdAt: 'asc' },
        }),
        prisma.purchaseOrder.findMany({
            where: { businessId, createdAt: { gt: sinceDate } },
            include: { items: true },
            take: limit,
            orderBy: { createdAt: 'asc' },
        }),
        prisma.deliveryChallan.findMany({
            where: { businessId, createdAt: { gt: sinceDate } },
            include: { items: true },
            take: limit,
            orderBy: { createdAt: 'asc' },
        }),
        prisma.return.findMany({
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
        prisma.stockMove.findMany({
            where: { businessId, createdAt: { gt: sinceDate } },
            take: limit,
            orderBy: { createdAt: 'asc' },
        }),
        prisma.syncQueueItem.findMany({
            where: { businessId, createdAt: { gt: sinceDate } },
            take: limit,
            orderBy: { createdAt: 'asc' },
        }),
    ]);
    for (const c of customers) {
        changes.push({
            entity: 'customer',
            entityId: fromScopedId(businessId, c.id),
            op: 'upsert',
            payload: JSON.stringify(c),
            timestamp: c.createdAt.toISOString(),
        });
    }
    for (const s of suppliers) {
        changes.push({
            entity: 'supplier',
            entityId: fromScopedId(businessId, s.id),
            op: 'upsert',
            payload: JSON.stringify(s),
            timestamp: s.createdAt.toISOString(),
        });
    }
    for (const p of products) {
        changes.push({
            entity: 'product',
            entityId: fromScopedId(businessId, p.id),
            op: 'upsert',
            payload: JSON.stringify(p),
            timestamp: p.createdAt.toISOString(),
        });
    }
    for (const inv of invoices) {
        changes.push({
            entity: 'invoice',
            entityId: fromScopedId(businessId, inv.id),
            op: 'upsert',
            payload: JSON.stringify(inv),
            timestamp: inv.createdAt.toISOString(),
        });
    }
    for (const q of quotations) {
        changes.push({
            entity: 'quotation',
            entityId: fromScopedId(businessId, q.id),
            op: 'upsert',
            payload: JSON.stringify(q),
            timestamp: q.createdAt.toISOString(),
        });
    }
    for (const so of salesOrders) {
        changes.push({
            entity: 'sales_order',
            entityId: fromScopedId(businessId, so.id),
            op: 'upsert',
            payload: JSON.stringify(so),
            timestamp: so.createdAt.toISOString(),
        });
    }
    for (const po of purchaseOrders) {
        changes.push({
            entity: 'purchase_order',
            entityId: fromScopedId(businessId, po.id),
            op: 'upsert',
            payload: JSON.stringify(po),
            timestamp: po.createdAt.toISOString(),
        });
    }
    for (const dc of deliveryChallans) {
        changes.push({
            entity: 'delivery_challan',
            entityId: fromScopedId(businessId, dc.id),
            op: 'upsert',
            payload: JSON.stringify(dc),
            timestamp: dc.createdAt.toISOString(),
        });
    }
    for (const ret of returns) {
        changes.push({
            entity: 'return',
            entityId: fromScopedId(businessId, ret.id),
            op: 'upsert',
            payload: JSON.stringify(ret),
            timestamp: ret.createdAt.toISOString(),
        });
    }
    for (const pay of payments) {
        changes.push({
            entity: 'payment',
            entityId: fromScopedId(businessId, pay.id),
            op: 'upsert',
            payload: JSON.stringify(pay),
            timestamp: pay.createdAt.toISOString(),
        });
    }
    for (const exp of expenses) {
        let payloadObj = { ...exp };
        if (exp.category === 'Purchase' && exp.description && exp.description.includes('<!--ITEMS:')) {
            try {
                const parts = exp.description.split('<!--ITEMS:');
                payloadObj.description = parts[0].trim() || null;
                payloadObj.items = JSON.parse(parts[1].replace('-->', '').trim());
            }
            catch (_) { }
        }
        changes.push({
            entity: exp.category === 'Purchase' ? 'purchase' : 'expense',
            entityId: fromScopedId(businessId, exp.id),
            op: 'upsert',
            payload: JSON.stringify(payloadObj),
            timestamp: exp.createdAt.toISOString(),
        });
    }
    for (const ba of bankAccounts) {
        changes.push({
            entity: 'bank_account',
            entityId: fromScopedId(businessId, ba.id),
            op: 'upsert',
            payload: JSON.stringify(ba),
            timestamp: ba.createdAt.toISOString(),
        });
    }
    for (const chq of cheques) {
        changes.push({
            entity: 'cheque',
            entityId: fromScopedId(businessId, chq.id),
            op: 'upsert',
            payload: JSON.stringify(chq),
            timestamp: chq.createdAt.toISOString(),
        });
    }
    for (const sm of stockMoves) {
        changes.push({
            entity: 'stock_move',
            entityId: fromScopedId(businessId, sm.id),
            op: 'upsert',
            payload: JSON.stringify(sm),
            timestamp: sm.createdAt.toISOString(),
        });
    }
    for (const sq of syncQueueItems) {
        changes.push({
            entity: sq.entity,
            entityId: fromScopedId(businessId, sq.entityId),
            op: sq.op,
            payload: sq.payload ?? JSON.stringify({ id: sq.entityId }),
            timestamp: sq.createdAt.toISOString(),
        });
    }
    // Deduplicate by entity:entityId, keeping latest event; if older has items and newer lacks items, preserve items
    changes.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
    const deduped = new Map();
    for (const c of changes) {
        const key = `${c.entity}:${c.entityId}`;
        const prev = deduped.get(key);
        if (prev && prev.payload && c.payload) {
            try {
                const prevObj = JSON.parse(prev.payload);
                const currObj = JSON.parse(c.payload);
                if (prevObj.items && (!currObj.items || currObj.items.length === 0)) {
                    currObj.items = prevObj.items;
                    c.payload = JSON.stringify(currObj);
                }
            }
            catch (_) { }
        }
        deduped.set(key, c);
    }
    const finalChanges = Array.from(deduped.values());
    finalChanges.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
    return {
        changes: finalChanges.slice(0, limit),
        serverTime: new Date().toISOString(),
    };
}
