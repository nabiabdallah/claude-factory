# Spec: Transfer between own-bank accounts

- Status: Approved (sample — already implemented in the starter)
- Owner: <you>
- Related ADRs: 0001

## Problem
Customers need to move money between two accounts held at the bank, safely under retries.

## Scope
**In:** same-currency transfer between two existing accounts, idempotent by client key.
**Out:** FX, cross-bank payments, scheduling, limits, persistence beyond in-memory.

## Contract
`POST /transfers`, header `Idempotency-Key` (required).
Request: `{ "fromAccount", "toAccount", "amount": "decimal string", "currency": "ISO-4217" }`
Response 200: `{ "transferId", "remainingBalance", "currency" }`
Errors: RFC 9457 problem+json.

## Acceptance criteria
1. Given sufficient funds, a transfer debits source and credits target by the exact amount.
2. Given insufficient funds, the transfer fails with 422 and no balance changes.
3. Repeating a request with the same Idempotency-Key returns the original result and moves money once.
4. A zero or negative amount is rejected.
5. A currency different from the accounts' currency is rejected with 422.
6. An unknown account returns 404.
7. Error messages never contain a full account identifier.

## Failure modes
See criteria 2, 4–6. Same source and target → 400.

## Non-functional
Amounts are BigDecimal with currency minor-unit scale, HALF_EVEN rounding.
