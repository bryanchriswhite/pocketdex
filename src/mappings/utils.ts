import {CosmosBlock, CosmosEvent, CosmosMessage, CosmosTransaction} from "@subql/types-cosmos";
import {Account, UnprocessedEntity} from "../types";
import {createHash} from "crypto";

export type Primitive = CosmosEvent | CosmosMessage | CosmosTransaction | CosmosBlock;

export interface Primitives {
  event?: CosmosEvent;
  msg?: CosmosMessage;
  tx?: CosmosTransaction;
  block?: CosmosBlock;
}

// messageId returns the id of the message passed or
// that of the message which generated the event passed.
export function messageId(msg: CosmosMessage | CosmosEvent): string {
  return `${msg.tx.hash}-${msg.idx}`;
}

export async function checkBalancesAccount(address: string, chainId: string) {
  let accountEntity = await Account.get(address);
  if (typeof (accountEntity) === "undefined") {
    accountEntity = Account.create({id: address, chainId});
    await accountEntity.save();
  }
}

export function getTimeline(entity: CosmosMessage|CosmosEvent): bigint {
  const K2 = 100, K1 = K2 * 1000;
  const txIndex = entity.tx.idx;
  const blockHeight = entity.block.block.header.height;
  // check if entity is Event or Message, and set msgIndex appropriately
  const msgIndex = (<CosmosEvent>entity).msg?.idx === undefined ?
    (<CosmosMessage>entity).idx : (<CosmosEvent>entity).msg.idx;
  const timeline = (K1 * blockHeight) + (K2 * txIndex) + msgIndex;
  return BigInt(timeline);
}

export async function attemptHandling(input: Primitive,
  handlerFn: (primitive: any) => Promise<void>,
  errorFn: (Error: Error, Primitive: any) => void): Promise<void> {
  try {
    await handlerFn(input);
  } catch (error: unknown) {
    errorFn(error as Error, input);
  }
}

export async function unprocessedEventHandler(err: Error, event: CosmosEvent): Promise<void> {
  await trackUnprocessed(err, primitivesFromEvent(event));
}

export function primitivesFromTx(tx: CosmosTransaction): Primitives {
  return {block: tx.block, tx: tx};
}

export function primitivesFromMsg(msg: CosmosMessage): Primitives {
  return {block: msg.block, tx: msg.tx};
}

export function primitivesFromEvent(event: CosmosEvent): Primitives {
  return {block: event.block, tx: event.tx};
}

export async function trackUnprocessed(error: Error, primitives: Primitives): Promise<void> {
  logger.warn(`[trackUnprocessable] (error.message): ${error.message}`);
  logger.warn(`[trackUnprocessable] (error.stack): ${error.stack}`);
  // NB: failsafe try/catch
  try {
    const {event, msg, tx, block} = primitives;
    const sha256 = createHash("sha256");
    // NB: use error stack if no primitives available (i.e. block handler).
    const hashInput = event ?
        (event.tx ? messageId(event): `${event.block.blockId}-${event.idx}`) : msg ?
      // messageId(event) : msg ?
        messageId(msg) : tx ?
          tx.hash : block ?
            block.block.id : error.stack;
    sha256.write(hashInput);
    sha256.end();
    // NB: ID is base64 encoded representation of the sha256 of either:
    // 1. the conventional ID of the "highest-level" primitive available or
    // 2. the error stacktrace, if none are available (i.e. handle block error)
    const id = sha256.read().toString("base64");
    const eventId = event ? messageId(event) : undefined;
    const _messageId = event ? messageId(event) : undefined;
    const transactionId = tx ? tx.hash : undefined;
    const blockId = block ? block.block.id : "";

    const unprocessedEntity = UnprocessedEntity.create({
      id,
      error: error.stack || "",
      eventId,
      messageId: _messageId,
      transactionId,
      blockId: blockId,
    });
    return await unprocessedEntity.save();
  } catch {
    logger.error("[trackUnprocessable] (ERROR): unable to persist unprocessable entity");
    logger.error(`[trackUnprocessable] (ERROR | stack): ${error.stack}`);
  }
}
