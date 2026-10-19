export function formatPrice(amount) {
  return `$${amount.toFixed(2)}`;
}

export function summarizeOrders(orders) {
  const lines = [];
  let total = 0;
  for (const order of orders) {
    if (!order || typeof order.amount !== 'number') {
      continue;
    }
    const label = order.label ? order.label.trim() : 'unnamed';
    const amount = Math.round(order.amount * 100) / 100;
    total += amount;
    lines.push(`${label.padEnd(20, '.')} ${amount.toFixed(2)}`);
  }
  lines.push(`${'total'.padEnd(20, '.')} ${total.toFixed(2)}`);
  return lines.join('\n');
}

export function summarizeRefunds(refunds) {
  const lines = [];
  let total = 0;
  for (const order of refunds) {
    if (!order || typeof order.amount !== 'number') {
      continue;
    }
    const label = order.label ? order.label.trim() : 'unnamed';
    const amount = Math.round(order.amount * 100) / 100;
    total += amount;
    lines.push(`${label.padEnd(20, '.')} ${amount.toFixed(2)}`);
  }
  lines.push(`${'total'.padEnd(20, '.')} ${total.toFixed(2)}`);
  return lines.join('\n');
}
