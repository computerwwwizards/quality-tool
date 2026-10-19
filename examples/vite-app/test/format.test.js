import { expect, it } from 'vitest';
import { formatPrice } from '../src/format.js';

it('formats a price with two decimals', () => {
  expect(formatPrice(3)).toBe('$3.00');
});
