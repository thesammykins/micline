// OpenPencil 0.15.1: eval <canonical.fig> --code "$(cat windows-native.js)" --write
// Additive Windows adaptation; never regenerate or remove the macOS pages.
// These editable shapes are design references, not native runtime evidence.
await figma.loadFontAsync({family: 'Inter', style: 'Regular'});
const page = figma.createPage(); page.name = 'Windows · Native test build'; figma.currentPage = page;
const paint = h => [{type: 'SOLID', color: {r: parseInt(h.slice(1,3),16)/255, g: parseInt(h.slice(3,5),16)/255, b: parseInt(h.slice(5,7),16)/255}}];
function box(p, name, x, y, w, h, color = '#FFFFFF') {
  const n = figma.createFrame(); p.appendChild(n); n.name = name;
  n.x = x; n.y = y; n.resize(w,h); n.fills = paint(color); n.clipsContent = false; return n;
}
function text(p, value, x, y, w, size = 15) {
  const n = figma.createText(); p.appendChild(n); n.name = value;
  n.fontName = {family:'Inter', style:'Regular'}; n.fontSize = size;
  n.characters = value; n.x = x; n.y = y; n.resize(w,22); n.textAutoResize = 'HEIGHT'; n.fills = paint('#202020'); return n;
}
function control(p, value, x, y, w, h = 28) {
  const n = box(p,value || 'Empty selector',x,y,w,h,'#F5F5F5');
  n.strokes = paint('#A0A0A0'); n.strokeWeight = 1; text(n,value,8,5,w-16,14); return n;
}
const states = [
  ['Empty', '', 'No input endpoints found. Connect a microphone and Rescan.'],
  ['Configured', 'Studio Microphone', 'Ready — press Start to begin processing.'],
  ['Active', 'Studio Microphone', 'Processing — input is routed to VB-CABLE.'],
  ['Recovery', '', 'Stopped — saved microphone is unavailable.'],
];
for (let i=0;i<states.length;i++) {
  const [name,input,status] = states[i];
  const frame = box(page,`Windows / ${name}`,i*680,0,620,590,'#F0F0F0');
  const title = box(frame,'Native Windows titlebar',0,0,620,32,'#F3F3F3');
  text(title,'MicLine — Windows test build',16,7,430,14); text(title,'−     □     ×',510,7,105,14);
  const body = box(frame,'Route · Levels · Controls',0,32,604,550,'#F0F0F0');
  text(body,'Microphone',24,22,120); control(body,input,150,18,425);
  text(body,'Input channel',24,62,120); control(body,input?'Channel 1':'',150,58,160);
  text(body,'Virtual output',24,102,120); control(body,name==='Empty'?'':'CABLE Input (VB-Audio Virtual Cable)',150,98,425);
  control(body,'Get VB-CABLE',330,137,130); control(body,'Rescan',470,137,105);
  for (const [label,y,active] of [['Input',183,'−18.4 / −10.2'],['Output',237,'−20.1 / −12.0']]) {
    text(body,`${label} level (RMS / sample peak)`,24,y,320,14);
    box(body,`${label} track`,24,y+25,350,18,'#E6E6E6');
    if (name==='Active') box(body,`${label} RMS`,24,y+25,230,18,'#008A5A');
    text(body,`${name==='Active'?active:'−90.0 / −90.0'} dBFS`,380,y+21,200,14);
  }
  for (const [label,y,value,position] of [['Input gain',306,'+0 dB',220],['[x] Low cut',350,'80 Hz',70]]) {
    text(body,label,24,y,120); box(body,`${label} slider`,150,y+7,330,4,'#C0C0C0');
    box(body,`${label} thumb`,150+position,y,10,20,'#0078D4'); text(body,value,490,y,85);
  }
  text(body,'[ ] Bypass low cut',24,390,240); control(body,'Microphone privacy settings',330,387,245);
  text(body,status,24,430,551); control(body,name==='Active'?'Pause':'Start',335,500,110,32); control(body,'Quit',465,500,110,32);
}
text(page,'Native Swift/WinSDK adaptation of the compact route → meters → everyday controls hierarchy. No plugins, monitoring or automatic capture in this first build. Actual Windows controls and system font take precedence over these editable reference shapes.',0,630,1250);
return {page:page.id, frames:page.children.filter(n=>n.type==='FRAME').map(n=>n.id)};
