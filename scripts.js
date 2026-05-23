// Обновление часов
function updateClock() {
  const d = new Date();
  document.getElementById('clock').textContent = d.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
}

// Загрузка и парсинг CSV с новой структурой
async function loadMenuFromCSV(csvFile) {
  try {
    const response = await fetch(csvFile);
    const text = await response.text();
    const lines = text.split('\n').filter(line => line.trim() !== '');
    
    const menuData = {
      salads: [],
      mains1: [],
      mains2: [],
      soups: [],
      sides: [],
      drinks: [],
      combos: {},      // { combo: [...], набор 1: [...], набор 2: [...], набор 3: [...] }
      comboPrices: {}  // цены для комбо/наборов
    };
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      
      if (!trimmed) continue;
      
      const parts = line.split(';').map(p => p.trim());
      
      if (parts.length < 5) continue;
      
      const goal = parts[0] || '';           // цель: комбо, набор 1, набор 2, набор 3 или пусто
      const category = parts[1] || '';       // Категория: Салаты, Первые блюда, Вторые блюда, Гарниры, Напитки
      const name = parts[2] || '';           // Наименование
      const portion = parts[3] || '';        // Порция
      const price = parts[4] || '';          // Цена
      
      if (!name || !price) continue;
      
      const item = { name, portion, price: parseInt(price) || 0 };
      
      // Определяем категорию для размещения в меню
      let targetCategory = null;
      const catLower = category.toLowerCase();
      const nameLower = name.toLowerCase();
      
      if (catLower.includes('салат')) {
        targetCategory = 'salads';
      } else if (catLower.includes('первые блюда') || catLower.includes('суп')) {
        targetCategory = 'soups';
      } else if (catLower.includes('вторые блюда')) {
        // Разделяем вторые блюда на две колонки
        const mains2Keywords = ['котлет', 'рыб', 'гриб', 'лобио', 'печен', 'шашлык', 'спагетти'];
        const isMains2 = mains2Keywords.some(kw => nameLower.includes(kw));
        targetCategory = isMains2 ? 'mains2' : 'mains1';
      } else if (catLower.includes('гарнир')) {
        targetCategory = 'sides';
      } else if (catLower.includes('напитк')) {
        targetCategory = 'drinks';
      }
      
      // Добавляем в соответствующую категорию меню
      if (targetCategory) {
        menuData[targetCategory].push(item);
      }
      
      // Обрабатываем наборы/комбо
      const goalLower = goal.toLowerCase().trim();
      if (goalLower === 'комбо' || goalLower.startsWith('набор')) {
        if (!menuData.combos[goalLower]) {
          menuData.combos[goalLower] = [];
          menuData.comboPrices[goalLower] = 0;
        }
        menuData.combos[goalLower].push(item);
        menuData.comboPrices[goalLower] += item.price;
      }
    }
    
    return menuData;
  } catch (error) {
    console.error('Error loading CSV:', error);
    return null;
  }
}

// Рендер элемента меню
function renderMenuItem(item) {
  return `
    <div class="item">
      <span class="item-name">${item.name}</span>
      <div class="item-meta">
        <span class="item-portion">${item.portion}</span>
        <span class="item-sep">/</span>
        <span class="item-price">${item.price} ₽</span>
      </div>
    </div>
  `;
}

// Рендер КОМБО карточки
function renderCombo(items, totalPrice) {
  const itemsHtml = items.map(item => `<span><strong>${item.name}</strong></span>`).join(' ');
  return `
    <div class="promo-card">
      <div class="promo-side"><span>КОМБО</span></div>
      <div class="promo-content">
        <div class="promo-desc">${itemsHtml}</div>
        <div class="promo-line"></div>
        <div class="promo-price">${totalPrice} ₽</div>
      </div>
    </div>
  `;
}

// Рендер НАБОР карточки
function renderSet(setName, items, totalPrice) {
  const itemsHtml = items.map(item => `<span><strong>${item.name}</strong></span>`).join(' ');
  return `
    <div class="promo-card">
      <div class="promo-side"><span>${setName}</span></div>
      <div class="promo-content">
        <div class="promo-desc">${itemsHtml}</div>
        <div class="promo-line"></div>
        <div class="promo-price">${totalPrice} ₽</div>
      </div>
    </div>
  `;
}

// Генерация карточек КОМБО (только для левого монитора)
function generateComboCards(menuData) {
  let html = '';
  
  if (menuData.combos['комбо']) {
    const items = menuData.combos['комбо'];
    const price = menuData.comboPrices['комбо'];
    html += renderCombo(items, price);
  }
  
  return html;
}

// Генерация карточек НАБОРОВ (только для правого монитора)
function generateSetCards(menuData) {
  let html = '';
  
  // Сортируем наборы по порядку: набор 1, набор 2, набор 3
  const setKeys = Object.keys(menuData.combos)
    .filter(key => key.startsWith('набор'))
    .sort((a, b) => a.localeCompare(b, 'ru', { numeric: true }));
  
  for (const key of setKeys) {
    const items = menuData.combos[key];
    const price = menuData.comboPrices[key];
    const setName = 'НАБОР №' + key.replace('набор ', '');
    html += renderSet(setName, items, price);
  }
  
  return html;
}

// Экспорт функций
window.updateClock = updateClock;
window.loadMenuFromCSV = loadMenuFromCSV;
window.renderMenuItem = renderMenuItem;
window.renderCombo = renderCombo;
window.renderSet = renderSet;
window.generateComboCards = generateComboCards;
window.generateSetCards = generateSetCards;
