const ST = {
dano: { n: 'Daño de ataque', s: 'DA', c: '#ff9a4d', i: 'M14 4h6v6L10 20l-6-6zM4 14l6 6M3 21l2-2' },
poder: { n: 'Poder de habilidad', s: 'PH', c: '#a58bff', i: 'M12 3v5M12 16v5M3 12h5M16 12h5M6 6l3 3M15 15l3 3M18 6l-3 3M9 15l-3 3' },
armadura: { n: 'Armadura', s: 'ARM', c: '#e0b04a', i: 'M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z' },
resmag: { n: 'Resistencia mágica', s: 'RM', c: '#4fc8ff', i: 'M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 8l4 2.3v4.4L12 17l-4-2.3v-4.4z' },
velatq: { n: 'Velocidad de ataque', s: 'VA', c: '#ffd36b', i: 'M5 6l6 6-6 6M12 6l6 6-6 6' },
celeridad: { n: 'Celeridad', s: 'CEL', c: '#b8f0ff', i: 'M7 3h10M7 21h10M8 3c0 5 8 5 8 9s-8 4-8 9M16 3c0 5-8 5-8 9' },
critico: { n: 'Golpe crítico', s: 'CRÍT', c: '#ff5d5d', i: 'M12 3v5M12 16v5M3 12h5M16 12h5M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6' },
velmov: { n: 'Velocidad de movimiento', s: 'VM', c: '#9fe36a', i: 'M3 17c4 0 6-2 8-6s5-6 10-6c-1 6-4 12-11 12H3zM8 14l4-4' },
penarm: { n: 'Penetración de armadura', s: 'PEN', c: '#ff7a59', i: 'M3 21L21 3M15 3h6v6M6 9l-2 2 9 9 2-2' },
penmag: { n: 'Penetración mágica', s: 'PEN M', c: '#d08bff', i: 'M3 21L13 11M13 11a4 4 0 1 1 4 4M17 7h.01' },
robo: { n: 'Robo de vida', s: 'RV', c: '#ff4d7a', i: 'M12 3C9 7 6 10 6 14a6 6 0 0 0 12 0c0-4-3-7-6-11zM10 13l2 3 2-3' },
omni: { n: 'Omnivampirismo', s: 'OMNI', c: '#e66bc4', i: 'M8 4C6 7 4 9 4 12a4 4 0 0 0 8 0c0-3-2-5-4-8zM16 8c-2 3-4 5-4 8a4 4 0 0 0 8 0c0-3-2-5-4-8z' },
alcance: { n: 'Alcance', s: 'ALC', c: '#c3ccd3', i: 'M3 12h18M7 8l-4 4 4 4M17 8l4 4-4 4' },
tenacidad: { n: 'Tenacidad', s: 'TEN', c: '#9a7bff', i: 'M12 7a2 2 0 1 0 0-4a2 2 0 1 0 0 4M12 7v14M5 14a7 7 0 0 0 14 0M8 11h8' },
curacion: { n: 'Curación y escudos', s: 'CUR', c: '#4fe39a', i: 'M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6zM12 9v6M9 12h6' },
regen: { n: 'Regeneración', s: 'REG', c: '#6fe0a0', i: 'M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10zM12 10v5M9.5 12.5h5' }
};
const stat = (k, v, zeroDim) => { const s = ST[k]; const zero = /^0([ ,.]0+)?\s?%?$|^0 \| 0 ?%$/.test(v); return { n: s.n, s: s.s, c: s.c, i: s.i, v, bg: s.c + '22', vc: zero && zeroDim !== false ? '#7c8992' : '#eef2f4' }; };
