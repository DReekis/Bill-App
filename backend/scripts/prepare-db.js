import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const targetProvider = process.argv[2] || process.env.DB_PROVIDER || 'postgresql';
const schemaPath = path.resolve(__dirname, '../prisma/schema.prisma');

if (!fs.existsSync(schemaPath)) {
  console.error(`Error: schema.prisma not found at ${schemaPath}`);
  process.exit(1);
}

let content = fs.readFileSync(schemaPath, 'utf8');

if (targetProvider === 'postgresql' || targetProvider === 'postgres') {
  console.log('Configuring Prisma datasource for PostgreSQL (AWS Cloud RDS)...');
  content = content.replace(
    /datasource\s+db\s*\{[\s\S]*?\}/,
    `datasource db {\n  provider = "postgresql"\n  url      = env("DATABASE_URL")\n}`
  );
} else if (targetProvider === 'sqlite') {
  console.log('Configuring Prisma datasource for SQLite (Local Development)...');
  content = content.replace(
    /datasource\s+db\s*\{[\s\S]*?\}/,
    `datasource db {\n  provider = "sqlite"\n  url      = "file:./dev.db"\n}`
  );
} else {
  console.error(`Unsupported provider: ${targetProvider}. Use "postgresql" or "sqlite".`);
  process.exit(1);
}

fs.writeFileSync(schemaPath, content, 'utf8');
console.log(`Prisma schema successfully updated to provider "${targetProvider}".`);
