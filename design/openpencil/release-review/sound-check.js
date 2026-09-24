// Run against the original FIG with OpenPencil eval --stdin -o <candidate.fig>.
// Original artboards are preserved; this page is a proposal, not runtime evidence.
await figma.loadFontAsync({family:'Inter',style:'Regular'});
await figma.loadFontAsync({family:'Inter',style:'Bold'});
const page = figma.createPage(); page.name = 'Guided Sound Check'; figma.currentPage = page;
const C={bg:'#202124',panel:'#292B30',line:'#41444C',text:'#F4F5F7',muted:'#B0B5BF',green:'#42D99A',amber:'#FFCE66',red:'#FF7279',blue:'#83B5FF'};
const rgb=h=>({r:parseInt(h.slice(1,3),16)/255,g:parseInt(h.slice(3,5),16)/255,b:parseInt(h.slice(5,7),16)/255});
const paint=h=>[{type:'SOLID',color:rgb(h)}];
function box(parent,name,x,y,w,h,color=C.panel,r=12){const n=figma.createFrame();n.name=name;parent.appendChild(n);n.x=x;n.y=y;n.resize(w,h);n.fills=paint(color);n.cornerRadius=r;n.clipsContent=false;return n;}
function text(parent,value,x,y,w,size=13,color=C.text,bold=false){const n=figma.createText();parent.appendChild(n);n.name=value;n.fontName={family:'Inter',style:bold?'Bold':'Regular'};n.fontSize=size;n.characters=value;n.fills=paint(color);n.x=x;n.y=y;n.resize(w,Math.ceil(size*1.4)*value.split('\n').length);n.textAutoResize='HEIGHT';return n;}
function button(p,label,x,y,w,primary=false){const b=box(p,label,x,y,w,32,primary?'#326BC4':'#383B43',8);text(b,label,12,8,w-20,12);return b;}
function note(p,value,x,y,w){return text(p,value,x,y,w,12,C.muted);}
function board(name,x,y,w,h){const b=box(page,name,x,y,w,h,C.bg,16);b.strokes=paint(C.line);b.strokeWeight=1;return b;}
function toggle(p,name,x,y,on=true){const n=box(p,name,x,y,34,20,on?'#258664':'#515661',10);box(n,'Native switch thumb',on?16:2,2,16,16,'#F4F5F7',8);return n;}
function title(p,name,status=''){const t=box(p,'Native titlebar',0,0,p.width,48,'#2D2F34',16);text(t,'●  ●  ●',16,16,64,12,C.muted);text(t,name,92,15,Math.min(280,p.width-108),14,C.text,true);if(status)text(t,status,p.width-196,16,168,12,C.green);}
function meter(p,label,y,rms,peak,held,clip=false,w=640){
 const m=box(p,label+' meter',16,y,w,72,'#16191E',12);
 text(m,label,12,9,80,12,C.text,true);text(m,`RMS ${rms<=-90?'−∞':rms.toFixed(1)}`,94,9,115,12,C.muted);
 text(m,`PEAK ${peak<=-90?'−∞':peak.toFixed(1)}  ·  HOLD ${held<=-90?'−∞':held.toFixed(1)}`,222,9,w-300,12,C.text);
 if(clip)text(m,'CLIP',w-52,9,46,11,C.red,true);
 const width=w-24,track=box(m,'Rounded dBFS track',12,33,width,18,'#30343C',9);
 const pos=db=>Math.max(0,Math.min(1,(db+90)/90));
 if(rms>-90){const fillWidth=width*pos(rms);const fill=box(track,'RMS level',0,0,fillWidth,18,C.green,9);fill.clipsContent=true;
  if(rms>-18)box(fill,'Amber headroom zone',width*.8,0,Math.max(1,fillWidth-width*.8),18,C.amber,0);
  if(rms>-9)box(fill,'Red headroom zone',width*.9,0,Math.max(1,fillWidth-width*.9),18,C.red,0);
  const sheen=box(fill,'Static highlight',2,2,Math.max(1,fillWidth-4),4,'#FFFFFF',2);sheen.opacity=.13;
 }
 if(peak>-90)box(track,'Sample peak',Math.min(width-2,width*pos(peak)),1,2,16,'#FFFFFF',1);
 if(held>-90)box(track,'Held peak',Math.min(width-2,width*pos(held)),0,2,18,held>=-9?C.red:held>=-18?C.amber:C.green,1);
 for(const db of [-90,-60,-36,-18,-9,0])text(m,db===0?'0 dBFS':String(db).replace('-','−'),12+Math.min(width-43,width*pos(db)),56,48,9,db>=-9?C.red:db>=-18?C.amber:C.muted);
 return m;
}

const b=board('Sound check · raw microphone',0,0,720,650);title(b,'MicLine · Sound check','● Listening');
text(b,'Find your comfortable level',28,78,660,26,C.text,true);
note(b,'MICROPHONE   Studio Interface · Input 2',28,125,640);
const levels=box(b,'Live raw microphone',24,167,672,114,'#101216',16);
meter(levels,'RAW MIC',12,-25.4,-12.3,-8.6,false,640);
note(b,'Your voice stays here. Nothing is sent to an output during this check.',28,298,650);
const coach=box(b,'Attached coaching card',192,336,500,202,'#343B47',16);
text(coach,'2 of 5 · Leave room for louder moments',20,18,460,15,C.text,true);
note(coach,'Say a sentence at your usual volume, then try your louder voice.\nAdjust the gain on your microphone or interface if needed.',20,54,460);
text(coach,'● Good headroom for this sample',20,112,460,14,C.green,true);
note(coach,'Aim for speaking peaks around −18 to −6 dBFS.\nThis is a starting point, not a score for your voice.',20,143,460);
button(b,'Stop listening',28,566,150);button(b,'Back',306,566,80);button(b,'Skip',398,566,80);button(b,'Continue',490,566,202,true);
const d=board('Sound check · optional demonstration',780,0,720,650);title(d,'MicLine · Sound check');
text(d,'Make speech more even',28,78,660,26,C.text,true);
note(d,'A compressor softens louder words. Start gently and compare.',28,125,660);
const effect=box(d,'Compressor lesson',24,172,672,112);
text(effect,'Apple dynamics · Gentle speech',20,20,620,17,C.text,true);
button(effect,'Preview',20,61,112,true);button(effect,'Undo',144,61,90);button(effect,'Show me',480,61,164);
const demo=box(d,'Optional captioned demo player',280,312,416,222,'#13171D',16);
text(demo,'EXAMPLE · 12 SECOND DEMO',16,16,350,10,C.muted,true);
text(demo,'Louder words, gently softened.',16,57,380,19,C.text,true);
note(demo,'Video placeholder — record the final app UI.\nYour microphone is not being recorded.',16,94,380);
button(demo,'Play',16,162,80);button(demo,'Read steps',108,162,126);button(demo,'Close',314,162,86);
note(d,'Optional effects can be skipped. Keep saves the preview; Undo restores it.',28,552,660);
button(d,'Skip compressor',28,594,180);button(d,'Keep and continue',474,594,222,true);
return {page:page.id,artboards:page.children.map(n=>({id:n.id,name:n.name}))};
