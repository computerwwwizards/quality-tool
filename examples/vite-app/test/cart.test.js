import { describe, expect, it } from 'vitest';
import { applyDiscount, cartTotal } from '../src/cart.js';

describe('cartTotal', () => {
  it('sums price times quantity', () => {
    expect(cartTotal([{ price: 2, quantity: 3 }, { price: 1, quantity: 1 }])).toBe(7);
  });
});

describe('applyDiscount', () => {
  it('halves the total for HALF', () => {
    expect(applyDiscount(40, 'HALF')).toBe(20);
  });
});
