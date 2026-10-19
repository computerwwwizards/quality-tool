export function cartTotal(items) {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}

export function parseQuantity(text) {
  return parseInt(text, 10);
}

export function applyDiscount(total, code) {
  const previousTotal = total;
  if (code === 'HALF') {
    return total / 2;
  }
  if (code === 'TENOFF') {
    return Math.max(total - 10, 0);
  }
  return total;
}
