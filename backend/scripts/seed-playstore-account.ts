import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function seedPlayStoreTestAccount(): Promise<void> {
  const testPhone = '9999999999';
  const testEmail = 'playstore.test@billapp.in';

  console.log('[Seed] Ensuring Google Play Reviewer test account...');

  // 1. User
  let user = await prisma.user.findFirst({
    where: {
      OR: [
        { email: testEmail },
        { email: `${testPhone}@phone.billapp.in` },
      ],
    },
    include: { businesses: true },
  });

  if (!user) {
    user = await prisma.user.create({
      data: {
        name: 'Google Play Reviewer',
        email: testEmail,
        passwordHash: 'PLAYSTORE_REVIEWER_AUTH',
        role: 'owner',
      },
      include: { businesses: true },
    });
    console.log('[Seed] Created User:', user.name, user.email);
  } else {
    console.log('[Seed] Found existing User:', user.name, user.email);
  }

  // 2. Business
  let business = user.businesses.find((b) => b.name === 'Billket Superstore') || user.businesses[0];

  if (!business) {
    business = await prisma.business.create({
      data: {
        name: 'Billket Superstore',
        ownerName: 'Google Play Reviewer',
        phone: testPhone,
        email: testEmail,
        address: 'Shop #12, MG Road Commercial Complex',
        state: 'Karnataka',
        city: 'Bengaluru',
        pinCode: '560001',
        country: 'India',
        gstin: '29AABCU9603R1ZM',
        pan: 'AABCU9603R',
        industry: 'Retail',
        taxRegistered: true,
        compositionScheme: false,
        invoicePrefix: 'INV',
        invoiceSequence: 10,
        allowNegativeStock: false,
        fyStart: '2026-04-01',
        currency: 'INR',
        subscriptionTier: 'pro',
        subscriptionStatus: 'active',
        subscriptionExpiresAt: null,
        maxDevices: 10,
        ownerId: user.id,
      },
    });
    console.log('[Seed] Created Business:', business.name, business.id);
  } else {
    business = await prisma.business.update({
      where: { id: business.id },
      data: {
        name: 'Billket Superstore',
        ownerName: 'Google Play Reviewer',
        phone: testPhone,
        email: testEmail,
        address: 'Shop #12, MG Road Commercial Complex',
        state: 'Karnataka',
        city: 'Bengaluru',
        pinCode: '560001',
        gstin: '29AABCU9603R1ZM',
        pan: 'AABCU9603R',
        taxRegistered: true,
        subscriptionTier: 'pro',
        subscriptionStatus: 'active',
        subscriptionExpiresAt: null,
      },
    });
    console.log('[Seed] Updated Business to Pro Tier:', business.name);
  }

  const businessId = business.id;

  // 3. Products
  const productsCount = await prisma.product.count({ where: { businessId } });
  if (productsCount === 0) {
    console.log('[Seed] Seeding sample products...');
    const demoProducts = [
      {
        name: 'Premium A4 Copier Paper (75 GSM)',
        sku: 'PAP-001',
        category: 'Office Supplies',
        hsn: '4802',
        gstRate: 18,
        purchasePrice: 20000,
        salePrice: 32000,
        mrp: 42000,
        stock: 40,
        costAverage: 20000,
        lowStockThreshold: 10,
        unit: 'ream',
      },
      {
        name: 'Thermal POS Receipt Roll (3 inch)',
        sku: 'ROL-014',
        category: 'Billing Supplies',
        hsn: '4821',
        gstRate: 12,
        purchasePrice: 5500,
        salePrice: 8500,
        mrp: 12000,
        stock: 25,
        costAverage: 5500,
        lowStockThreshold: 10,
        unit: 'roll',
      },
      {
        name: 'Logitech Wireless Optical Mouse',
        sku: 'ELC-031',
        category: 'Electronics',
        hsn: '8471',
        gstRate: 18,
        purchasePrice: 45000,
        salePrice: 89900,
        mrp: 129900,
        stock: 15,
        costAverage: 45000,
        lowStockThreshold: 5,
        unit: 'pc',
      },
      {
        name: 'Boat Stone Bluetooth Speaker 10W',
        sku: 'ELC-044',
        category: 'Electronics',
        hsn: '8518',
        gstRate: 18,
        purchasePrice: 75000,
        salePrice: 149900,
        mrp: 199900,
        stock: 12,
        costAverage: 75000,
        lowStockThreshold: 4,
        unit: 'pc',
      },
      {
        name: 'Mesh Desk Organizer (Black)',
        sku: 'ORG-220',
        category: 'Office Supplies',
        hsn: '3926',
        gstRate: 18,
        purchasePrice: 38000,
        salePrice: 64000,
        mrp: 84000,
        stock: 18,
        costAverage: 38000,
        lowStockThreshold: 5,
        unit: 'pc',
      },
    ];

    for (const p of demoProducts) {
      await prisma.product.create({
        data: {
          ...p,
          businessId,
        },
      });
    }
  }

  // 4. Customers
  const customerCount = await prisma.customer.count({ where: { businessId } });
  if (customerCount === 0) {
    console.log('[Seed] Seeding sample customers...');
    await prisma.customer.createMany({
      data: [
        {
          businessId,
          name: 'Meera Enterprises',
          phone: '9845012345',
          email: 'meera@example.com',
          state: 'Karnataka',
          city: 'Bengaluru',
          gstin: '29ABCDE1234F1Z5',
          creditLimit: 5000000,
          paymentTerms: 30,
        },
        {
          businessId,
          name: 'Northstar Retail Store',
          phone: '9821122334',
          email: 'accounts@northstar.in',
          state: 'Karnataka',
          city: 'Bengaluru',
          creditLimit: 2500000,
          paymentTerms: 15,
        },
        {
          businessId,
          name: 'Aarav General Mart',
          phone: '9611456789',
          email: 'aarav@example.com',
          state: 'Karnataka',
          city: 'Mysuru',
          creditLimit: 1000000,
          paymentTerms: 7,
        },
      ],
    });
  }

  // 5. Suppliers
  const supplierCount = await prisma.supplier.count({ where: { businessId } });
  if (supplierCount === 0) {
    console.log('[Seed] Seeding sample suppliers...');
    await prisma.supplier.createMany({
      data: [
        {
          businessId,
          name: 'Paper House Wholesale',
          phone: '9880011223',
          email: 'sales@paperhouse.in',
          state: 'Karnataka',
          gstin: '29AABCP1122K1Z1',
          creditPeriod: 30,
        },
        {
          businessId,
          name: 'TechDirect Distributors',
          phone: '9899022110',
          email: 'orders@techdirect.com',
          state: 'Karnataka',
          gstin: '29AACCP7788Q1Z8',
          creditPeriod: 15,
        },
      ],
    });
  }

  // 6. Bank Account
  const bankCount = await prisma.bankAccount.count({ where: { businessId } });
  if (bankCount === 0) {
    console.log('[Seed] Seeding sample bank account...');
    await prisma.bankAccount.create({
      data: {
        businessId,
        bankName: 'HDFC Bank',
        accountName: 'Current Account',
        accountNumber: '50200012345678',
        openingBalance: 25000000,
      },
    });
  }

  // 7. Sample Invoices
  const invoiceCount = await prisma.invoice.count({ where: { businessId } });
  if (invoiceCount === 0) {
    console.log('[Seed] Seeding sample invoice...');
    const firstCustomer = await prisma.customer.findFirst({ where: { businessId } });
    if (firstCustomer) {
      await prisma.invoice.create({
        data: {
          businessId,
          number: 'INV-001',
          customerId: firstCustomer.id,
          customerName: firstCustomer.name,
          date: new Date(),
          dueDate: new Date(Date.now() + 15 * 86400000),
          gstType: 'gst',
          subtotal: 32000,
          discount: 0,
          discountRate: 0,
          taxable: 32000,
          tax: 5760,
          cgst: 2880,
          sgst: 2880,
          igst: 0,
          total: 37760,
          amountPaid: 37760,
          paymentMode: 'UPI',
          status: 'Finalized',
          notes: 'Google Play review demo invoice - Paid via UPI',
        },
      });
    }
  }

  console.log('[Seed] Google Play Reviewer test account ready with full features!');
}

// Direct execution
if (import.meta.url === `file://${process.argv[1]}`) {
  seedPlayStoreTestAccount()
    .catch((err) => {
      console.error('[Seed] Error:', err);
      process.exit(1);
    })
    .finally(() => prisma.$disconnect());
}
