import { cartTotal } from './cart.js';
import { formatPrice } from './format.js';

const items = [
  { price: 12.5, quantity: 2 },
  { price: 3, quantity: 1 },
];

document.querySelector('#app').textContent = formatPrice(cartTotal(items));
