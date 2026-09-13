import { prisma } from './db.js';

export async function enqueueSync(input: {
  businessId: string;
  entity: string;
  entityId: string;
  op: 'upsert' | 'delete';
  payload: string;
}) {
  return await prisma.syncQueueItem.create({
    data: {
      businessId: input.businessId,
      entity: input.entity,
      entityId: input.entityId,
      op: input.op,
      payload: input.payload,
      status: 'pending',
    },
  });
}
