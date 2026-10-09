import crypto from 'crypto';
import Razorpay from 'razorpay';
import { config } from '../config.js';
import { prisma } from './db.js';

export interface PlanFeatureMatrix {
  id: string;
  name: string;
  tier: 'free' | 'starter' | 'silver' | 'gold' | 'business_pro';
  priceInInr: number;
  amountInPaise: number;
  currency: string;
  billingCycle: 'annual';
  badge?: string;
  popular?: boolean;
  limits: {
    salesInvoicesPerYear: number; // -1 = Unlimited
    purchasesPerYear: number;     // -1 = Unlimited
    customers: number;            // -1 = Unlimited
    suppliers: number;            // -1 = Unlimited
    items: number;                // -1 = Unlimited
    companies: number;
    staffUsers: number;           // -1 = Unlimited
    eWayBillsPerMonth: number;    // -1 = Unlimited
    whatsAppInvoicesPerMonth: number; // -1 = Unlimited
    restoreDeletedTransactionsCount: number; // -1 = Unlimited
  };
  features: {
    android: boolean;
    windowsDesktop: boolean;
    gstBilling: boolean;
    nonGstBilling: boolean;
    salesReturn: boolean;
    purchaseReturn: boolean;
    estimateQuotation: boolean;
    salesOrder: boolean;
    purchaseOrder: boolean;
    deliveryChallan: boolean;
    stockManagement: 'basic' | 'advanced';
    multiplePricing: boolean;
    discount: boolean;
    barcode: boolean;
    lowStockAlert: boolean;
    stockTransfer: boolean;
    expenseManagement: boolean;
    receivablePayable: boolean;
    paymentReminder: boolean;
    gstReports: boolean;
    eInvoice: boolean;
    eWayBill: boolean;
    profitLoss: 'none' | 'basic' | 'advanced';
    partyWiseProfitLoss: boolean;
    balanceSheet: boolean;
    accountingModule: boolean;
    bankManagement: boolean;
    tallyExport: boolean;
    whatsAppPaymentReminder: boolean;
    multiDeviceSync: boolean;
    userPermissions: 'none' | 'basic' | 'advanced';
    customerLoyalty: boolean;
    advancedReports: boolean;
    excelExport: boolean;
    dataBackup: 'none' | 'daily' | 'automatic';
    restoreDeletedTransactions: boolean;
    prioritySupport: boolean;
    personalRM: boolean;
    nearExpiryAlert: boolean;
    invoiceSetting: boolean;
  };
  highlights: string[];
}

export const SUBSCRIPTION_PLANS: Record<string, PlanFeatureMatrix> = {
  free: {
    id: 'free',
    name: 'Free Plan',
    tier: 'free',
    priceInInr: 0,
    amountInPaise: 0,
    currency: 'INR',
    billingCycle: 'annual',
    limits: {
      salesInvoicesPerYear: 10,
      purchasesPerYear: 10,
      customers: 50,
      suppliers: 50,
      items: 100,
      companies: 1,
      staffUsers: 1,
      eWayBillsPerMonth: 0,
      whatsAppInvoicesPerMonth: 20,
      restoreDeletedTransactionsCount: 0,
    },
    features: {
      android: true,
      windowsDesktop: false,
      gstBilling: true,
      nonGstBilling: true,
      salesReturn: false,
      purchaseReturn: false,
      estimateQuotation: false,
      salesOrder: false,
      purchaseOrder: false,
      deliveryChallan: false,
      stockManagement: 'basic',
      multiplePricing: false,
      discount: true,
      barcode: false,
      lowStockAlert: false,
      stockTransfer: false,
      expenseManagement: true,
      receivablePayable: true,
      paymentReminder: false,
      gstReports: true,
      eInvoice: false,
      eWayBill: false,
      profitLoss: 'none',
      partyWiseProfitLoss: false,
      balanceSheet: false,
      accountingModule: false,
      bankManagement: false,
      tallyExport: false,
      whatsAppPaymentReminder: false,
      multiDeviceSync: false,
      userPermissions: 'none',
      customerLoyalty: false,
      advancedReports: false,
      excelExport: false,
      dataBackup: 'none',
      restoreDeletedTransactions: false,
      prioritySupport: false,
      personalRM: false,
      nearExpiryAlert: false,
      invoiceSetting: false,
    },
    highlights: [
      'Up to 10 Sales Invoices & 10 Purchases',
      '50 Customers & 50 Suppliers',
      '100 Item Catalog with Basic Stock',
      'GST & Non-GST Billing',
      '20 WhatsApp Invoices/month',
    ],
  },

  starter: {
    id: 'starter',
    name: 'Starter Plan',
    tier: 'starter',
    priceInInr: 579,
    amountInPaise: 57900,
    currency: 'INR',
    billingCycle: 'annual',
    limits: {
      salesInvoicesPerYear: -1,
      purchasesPerYear: -1,
      customers: 500,
      suppliers: 500,
      items: 1000,
      companies: 1,
      staffUsers: 1,
      eWayBillsPerMonth: 0,
      whatsAppInvoicesPerMonth: 500,
      restoreDeletedTransactionsCount: 0,
    },
    features: {
      android: true,
      windowsDesktop: false,
      gstBilling: true,
      nonGstBilling: true,
      salesReturn: true,
      purchaseReturn: true,
      estimateQuotation: true,
      salesOrder: false,
      purchaseOrder: false,
      deliveryChallan: false,
      stockManagement: 'basic',
      multiplePricing: true,
      discount: true,
      barcode: false,
      lowStockAlert: false,
      stockTransfer: false,
      expenseManagement: true,
      receivablePayable: true,
      paymentReminder: true,
      gstReports: true,
      eInvoice: false,
      eWayBill: false,
      profitLoss: 'basic',
      partyWiseProfitLoss: false,
      balanceSheet: false,
      accountingModule: false,
      bankManagement: false,
      tallyExport: false,
      whatsAppPaymentReminder: false,
      multiDeviceSync: false,
      userPermissions: 'none',
      customerLoyalty: false,
      advancedReports: true,
      excelExport: true,
      dataBackup: 'daily',
      restoreDeletedTransactions: false,
      prioritySupport: false,
      personalRM: false,
      nearExpiryAlert: false,
      invoiceSetting: false,
    },
    highlights: [
      'Unlimited Sales & Purchases',
      'Sales & Purchase Returns + Estimates/Quotations',
      '500 Customers & 500 Suppliers, 1,000 Items',
      'Multiple Price Lists & Payment Reminders',
      '500 WhatsApp Invoices/month & Daily Backup',
    ],
  },

  silver: {
    id: 'silver',
    name: 'Silver Plan',
    tier: 'silver',
    priceInInr: 1499,
    amountInPaise: 149900,
    currency: 'INR',
    billingCycle: 'annual',
    badge: 'Most Popular',
    popular: true,
    limits: {
      salesInvoicesPerYear: -1,
      purchasesPerYear: -1,
      customers: 2500,
      suppliers: 2500,
      items: 5000,
      companies: 2,
      staffUsers: 2,
      eWayBillsPerMonth: 10,
      whatsAppInvoicesPerMonth: -1,
      restoreDeletedTransactionsCount: 2,
    },
    features: {
      android: true,
      windowsDesktop: false,
      gstBilling: true,
      nonGstBilling: true,
      salesReturn: true,
      purchaseReturn: true,
      estimateQuotation: true,
      salesOrder: true,
      purchaseOrder: true,
      deliveryChallan: true,
      stockManagement: 'advanced',
      multiplePricing: true,
      discount: true,
      barcode: true,
      lowStockAlert: true,
      stockTransfer: true,
      expenseManagement: true,
      receivablePayable: true,
      paymentReminder: true,
      gstReports: true,
      eInvoice: true,
      eWayBill: true,
      profitLoss: 'basic',
      partyWiseProfitLoss: false,
      balanceSheet: false,
      accountingModule: false,
      bankManagement: true,
      tallyExport: true,
      whatsAppPaymentReminder: true,
      multiDeviceSync: true,
      userPermissions: 'basic',
      customerLoyalty: false,
      advancedReports: true,
      excelExport: true,
      dataBackup: 'automatic',
      restoreDeletedTransactions: true,
      prioritySupport: false,
      personalRM: false,
      nearExpiryAlert: false,
      invoiceSetting: true,
    },
    highlights: [
      'Sales/Purchase Orders & Delivery Challan',
      'Barcode Scanning & Low Stock Alerts',
      'Government E-Invoice IRN & 10 E-Way Bills/mo',
      'Bank Management Hub & Tally XML Export',
      'Multi-Device Sync, 2 Companies & 2 Users',
      'Unlimited WhatsApp Invoices & Reminders',
    ],
  },

  gold: {
    id: 'gold',
    name: 'Gold Plan',
    tier: 'gold',
    priceInInr: 2999,
    amountInPaise: 299900,
    currency: 'INR',
    billingCycle: 'annual',
    badge: 'Best Value',
    limits: {
      salesInvoicesPerYear: -1,
      purchasesPerYear: -1,
      customers: 10000,
      suppliers: 10000,
      items: 25000,
      companies: 5,
      staffUsers: 5,
      eWayBillsPerMonth: -1,
      whatsAppInvoicesPerMonth: -1,
      restoreDeletedTransactionsCount: -1,
    },
    features: {
      android: true,
      windowsDesktop: true,
      gstBilling: true,
      nonGstBilling: true,
      salesReturn: true,
      purchaseReturn: true,
      estimateQuotation: true,
      salesOrder: true,
      purchaseOrder: true,
      deliveryChallan: true,
      stockManagement: 'advanced',
      multiplePricing: true,
      discount: true,
      barcode: true,
      lowStockAlert: true,
      stockTransfer: true,
      expenseManagement: true,
      receivablePayable: true,
      paymentReminder: true,
      gstReports: true,
      eInvoice: true,
      eWayBill: true,
      profitLoss: 'advanced',
      partyWiseProfitLoss: true,
      balanceSheet: true,
      accountingModule: true,
      bankManagement: true,
      tallyExport: true,
      whatsAppPaymentReminder: true,
      multiDeviceSync: true,
      userPermissions: 'advanced',
      customerLoyalty: false,
      advancedReports: true,
      excelExport: true,
      dataBackup: 'automatic',
      restoreDeletedTransactions: true,
      prioritySupport: true,
      personalRM: true,
      nearExpiryAlert: true,
      invoiceSetting: true,
    },
    highlights: [
      'Windows & Desktop Support',
      '10,000 Customers & 25,000 Items Catalog',
      'Unlimited E-Way Bills & Unlimited Restores',
      'Full Accounting Module, Balance Sheet & Party P&L',
      '5 Companies & 5 Staff Users (Advanced RBAC)',
      'Priority Support & Dedicated Relationship Manager',
    ],
  },

  business_pro: {
    id: 'business_pro',
    name: 'Business Pro',
    tier: 'business_pro',
    priceInInr: 4999,
    amountInPaise: 499900,
    currency: 'INR',
    billingCycle: 'annual',
    badge: 'Enterprise',
    limits: {
      salesInvoicesPerYear: -1,
      purchasesPerYear: -1,
      customers: -1,
      suppliers: -1,
      items: -1,
      companies: 10,
      staffUsers: -1,
      eWayBillsPerMonth: -1,
      whatsAppInvoicesPerMonth: -1,
      restoreDeletedTransactionsCount: -1,
    },
    features: {
      android: true,
      windowsDesktop: true,
      gstBilling: true,
      nonGstBilling: true,
      salesReturn: true,
      purchaseReturn: true,
      estimateQuotation: true,
      salesOrder: true,
      purchaseOrder: true,
      deliveryChallan: true,
      stockManagement: 'advanced',
      multiplePricing: true,
      discount: true,
      barcode: true,
      lowStockAlert: true,
      stockTransfer: true,
      expenseManagement: true,
      receivablePayable: true,
      paymentReminder: true,
      gstReports: true,
      eInvoice: true,
      eWayBill: true,
      profitLoss: 'advanced',
      partyWiseProfitLoss: true,
      balanceSheet: true,
      accountingModule: true,
      bankManagement: true,
      tallyExport: true,
      whatsAppPaymentReminder: true,
      multiDeviceSync: true,
      userPermissions: 'advanced',
      customerLoyalty: true,
      advancedReports: true,
      excelExport: true,
      dataBackup: 'automatic',
      restoreDeletedTransactions: true,
      prioritySupport: true,
      personalRM: true,
      nearExpiryAlert: true,
      invoiceSetting: true,
    },
    highlights: [
      'Everything in Gold + Unlimited Everything',
      'Customer Loyalty Program & Rewards System',
      'Up to 10 Business Companies',
      'Unlimited Multi-User Staff Access',
      'Dedicated Enterprise Relationship Manager',
    ],
  },
};

// Aliases for compatibility
SUBSCRIPTION_PLANS['pro'] = SUBSCRIPTION_PLANS['business_pro'];

function getRazorpayClient(): Razorpay {
  return new Razorpay({
    key_id: config.razorpay.keyId,
    key_secret: config.razorpay.keySecret,
  });
}

/**
 * Creates an order directly with Razorpay server.
 * Guarantees price integrity by deriving amount exclusively from the verified plan catalog.
 */
export async function createSubscriptionOrder(params: {
  businessId: string;
  tier: string;
  userId?: string;
}) {
  const normalizedTier = params.tier.toLowerCase().trim().replace('-', '_');
  const plan = SUBSCRIPTION_PLANS[normalizedTier];

  if (!plan) {
    throw new Error('INVALID_PLAN_TIER');
  }

  if (plan.amountInPaise <= 0) {
    throw new Error('FREE_PLAN_CANNOT_BE_PURCHASED');
  }

  const business = await prisma.business.findUnique({
    where: { id: params.businessId },
  });

  if (!business) {
    throw new Error('BUSINESS_NOT_FOUND');
  }

  const receipt = `rcpt_${params.businessId.slice(-6)}_${Date.now().toString().slice(-6)}`;
  let rzpOrderId = '';

  try {
    const razorpay = getRazorpayClient();
    const order = await razorpay.orders.create({
      amount: plan.amountInPaise,
      currency: plan.currency,
      receipt,
      notes: {
        businessId: params.businessId,
        businessName: business.name,
        tier: plan.tier,
        planName: plan.name,
        billingCycle: plan.billingCycle,
        userId: params.userId ?? '',
      },
    });
    rzpOrderId = order.id;
  } catch (err: any) {
    // If Razorpay API rejects or keys need direct REST fallback
    console.warn('[Razorpay] Orders API fallback or error:', err?.message || err);
    throw new Error(`RAZORPAY_API_ERROR: ${err?.message || 'Failed to initialize payment order'}`);
  }

  // Persist order in database for non-repudiation and cryptographic audit trail
  const subscriptionOrder = await prisma.subscriptionOrder.create({
    data: {
      orderId: rzpOrderId,
      businessId: params.businessId,
      tier: plan.tier,
      amount: plan.amountInPaise,
      currency: plan.currency,
      status: 'created',
      receipt,
      notes: JSON.stringify({
        planName: plan.name,
        tier: plan.tier,
        userId: params.userId,
      }),
    },
  });

  return {
    orderId: rzpOrderId,
    amount: plan.amountInPaise,
    currency: plan.currency,
    keyId: config.razorpay.keyId,
    businessName: business.name,
    businessEmail: business.email || '',
    businessPhone: business.phone || '',
    plan: {
      id: plan.id,
      name: plan.name,
      priceInInr: plan.priceInInr,
      tier: plan.tier,
    },
  };
}

/**
 * Cryptographically verifies Razorpay payment signature using HMAC SHA-256.
 * Atomically updates business tier and sets annual expiration date.
 */
export async function verifySubscriptionPayment(params: {
  businessId: string;
  orderId: string;
  paymentId: string;
  signature: string;
  userId?: string;
}) {
  const { businessId, orderId, paymentId, signature } = params;

  if (!orderId || !paymentId || !signature) {
    throw new Error('MISSING_VERIFICATION_PARAMETERS');
  }

  // Cryptographic HMAC SHA-256 validation
  const generatedSignature = crypto
    .createHmac('sha256', config.razorpay.keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest('hex');

  if (generatedSignature !== signature) {
    throw new Error('SIGNATURE_VERIFICATION_FAILED');
  }

  // Look up order record
  const existingOrder = await prisma.subscriptionOrder.findUnique({
    where: { orderId },
  });

  if (!existingOrder) {
    throw new Error('ORDER_NOT_FOUND');
  }

  if (existingOrder.businessId !== businessId) {
    throw new Error('BUSINESS_MISMATCH');
  }

  if (existingOrder.status === 'paid') {
    // Already processed idempotently
    return {
      success: true,
      alreadyProcessed: true,
      tier: existingOrder.tier,
      paymentId: existingOrder.paymentId,
    };
  }

  // Check replay protection for paymentId
  const existingPayment = await prisma.subscriptionOrder.findUnique({
    where: { paymentId },
  });
  if (existingPayment && existingPayment.id !== existingOrder.id) {
    throw new Error('PAYMENT_ALREADY_USED');
  }

  const now = new Date();
  const currentBusiness = await prisma.business.findUnique({
    where: { id: businessId },
  });

  // Calculate 1-year extension
  let expiresAt = new Date();
  if (
    currentBusiness?.subscriptionExpiresAt &&
    new Date(currentBusiness.subscriptionExpiresAt).getTime() > now.getTime()
  ) {
    expiresAt = new Date(currentBusiness.subscriptionExpiresAt);
    expiresAt.setFullYear(expiresAt.getFullYear() + 1);
  } else {
    expiresAt.setFullYear(now.getFullYear() + 1);
  }

  const plan = SUBSCRIPTION_PLANS[existingOrder.tier] || SUBSCRIPTION_PLANS['silver'];

  // Execute atomic state transition in transaction
  const result = await prisma.$transaction(async (tx) => {
    // 1. Mark order paid
    const updatedOrder = await tx.subscriptionOrder.update({
      where: { id: existingOrder.id },
      data: {
        status: 'paid',
        paymentId,
        signature,
        paidAt: now,
      },
    });

    // 2. Upgrade business subscription
    const updatedBusiness = await tx.business.update({
      where: { id: businessId },
      data: {
        subscriptionTier: existingOrder.tier,
        subscriptionStatus: 'active',
        subscriptionExpiresAt: expiresAt,
        maxDevices: plan.limits.staffUsers === -1 ? 99 : plan.limits.staffUsers,
      },
    });

    // 3. Record immutable audit log
    await tx.auditLog.create({
      data: {
        businessId,
        actorId: params.userId || null,
        action: 'SUBSCRIPTION_UPGRADED',
        entity: 'SubscriptionOrder',
        entityId: updatedOrder.id,
        before: JSON.stringify({ tier: currentBusiness?.subscriptionTier }),
        after: JSON.stringify({
          tier: existingOrder.tier,
          paymentId,
          orderId,
          expiresAt: expiresAt.toISOString(),
        }),
      },
    });

    return { updatedOrder, updatedBusiness };
  });

  return {
    success: true,
    tier: result.updatedBusiness.subscriptionTier,
    status: result.updatedBusiness.subscriptionStatus,
    expiresAt: result.updatedBusiness.subscriptionExpiresAt?.toISOString(),
    paymentId,
    orderId,
    planName: plan.name,
  };
}

/**
 * Verifies and handles webhooks dispatched by Razorpay.
 */
export async function handleRazorpayWebhook(params: {
  rawBody: string;
  signature: string;
}) {
  const { rawBody, signature } = params;

  const expectedSignature = crypto
    .createHmac('sha256', config.razorpay.webhookSecret)
    .update(rawBody)
    .digest('hex');

  if (expectedSignature !== signature) {
    throw new Error('INVALID_WEBHOOK_SIGNATURE');
  }

  const event = JSON.parse(rawBody);

  if (event.event === 'payment.captured' || event.event === 'order.paid') {
    const payment = event.payload?.payment?.entity;
    const order = event.payload?.order?.entity;
    const orderId = order?.id || payment?.order_id;
    const paymentId = payment?.id;

    if (orderId && paymentId) {
      const dbOrder = await prisma.subscriptionOrder.findUnique({
        where: { orderId },
      });

      if (dbOrder && dbOrder.status !== 'paid') {
        const now = new Date();
        const expiresAt = new Date();
        expiresAt.setFullYear(now.getFullYear() + 1);

        await prisma.$transaction(async (tx) => {
          await tx.subscriptionOrder.update({
            where: { id: dbOrder.id },
            data: {
              status: 'paid',
              paymentId,
              paidAt: now,
            },
          });

          await tx.business.update({
            where: { id: dbOrder.businessId },
            data: {
              subscriptionTier: dbOrder.tier,
              subscriptionStatus: 'active',
              subscriptionExpiresAt: expiresAt,
            },
          });
        });
      }
    }
  }

  return { received: true };
}

/**
 * Returns comprehensive subscription status, active tier capabilities,
 * usage counts, and remaining allowance.
 */
export async function getBusinessSubscriptionStatus(businessId: string) {
  const business = await prisma.business.findUnique({
    where: { id: businessId },
  });

  if (!business) {
    throw new Error('BUSINESS_NOT_FOUND');
  }

  const rawTier = (business.subscriptionTier || 'free').toLowerCase();
  const currentPlan = SUBSCRIPTION_PLANS[rawTier] || SUBSCRIPTION_PLANS['free'];

  // Check if expired
  const now = new Date();
  const isExpired = business.subscriptionExpiresAt
    ? new Date(business.subscriptionExpiresAt).getTime() < now.getTime()
    : false;

  const effectiveTier = isExpired ? 'free' : currentPlan.tier;
  const effectivePlan = SUBSCRIPTION_PLANS[effectiveTier] || SUBSCRIPTION_PLANS['free'];

  // Calculate current usage counts
  const [invoicesCount, customersCount, suppliersCount, productsCount] = await Promise.all([
    prisma.invoice.count({ where: { businessId } }),
    prisma.customer.count({ where: { businessId } }),
    prisma.supplier.count({ where: { businessId } }),
    prisma.product.count({ where: { businessId } }),
  ]);

  const daysRemaining = business.subscriptionExpiresAt
    ? Math.max(
        0,
        Math.ceil(
          (new Date(business.subscriptionExpiresAt).getTime() - now.getTime()) /
            (1000 * 60 * 60 * 24)
        )
      )
    : 0;

  return {
    businessId,
    businessName: business.name,
    tier: effectiveTier,
    planName: effectivePlan.name,
    status: isExpired ? 'expired' : business.subscriptionStatus,
    isExpired,
    daysRemaining,
    expiresAt: business.subscriptionExpiresAt ? business.subscriptionExpiresAt.toISOString() : null,
    plan: effectivePlan,
    usage: {
      invoices: {
        used: invoicesCount,
        limit: effectivePlan.limits.salesInvoicesPerYear,
        exceeded:
          effectivePlan.limits.salesInvoicesPerYear !== -1 &&
          invoicesCount >= effectivePlan.limits.salesInvoicesPerYear,
      },
      customers: {
        used: customersCount,
        limit: effectivePlan.limits.customers,
        exceeded:
          effectivePlan.limits.customers !== -1 &&
          customersCount >= effectivePlan.limits.customers,
      },
      suppliers: {
        used: suppliersCount,
        limit: effectivePlan.limits.suppliers,
        exceeded:
          effectivePlan.limits.suppliers !== -1 &&
          suppliersCount >= effectivePlan.limits.suppliers,
      },
      products: {
        used: productsCount,
        limit: effectivePlan.limits.items,
        exceeded:
          effectivePlan.limits.items !== -1 &&
          productsCount >= effectivePlan.limits.items,
      },
    },
  };
}
