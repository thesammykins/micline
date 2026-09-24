// Run against the original FIG with OpenPencil eval --stdin -o <candidate.fig>.
// Original artboards are preserved; this page is a proposal, not runtime evidence.
await figma.loadFontAsync({family:'Inter',style:'Regular'});
await figma.loadFontAsync({family:'Inter',style:'Bold'});
const page = figma.createPage(); page.name = 'Release Review'; figma.currentPage = page;
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
function main(name,x,count=2,stopped=false){
 const visible=Math.min(count,4), h=574+visible*56;
 const b=board(name,x,0,720,h);title(b,'MicLine');text(b,stopped?'Stopped':'● Processing',438,17,138,12,stopped?C.muted:C.green);button(b,stopped?'Start':'Stop',598,8,98,true);
 const route=box(b,'Route and channel selection',24,68,672,108);
 text(route,'MICROPHONE',14,12,280,10,C.muted,true);text(route,'PROCESSED OUTPUT',348,12,300,10,C.muted,true);
 text(route,'Studio Interface  ⌄',14,34,300,15);text(route,'Virtual Cable  ⌄',348,34,300,15);
 button(route,'Input 2 · Mono  ⌄',14,62,220);button(route,'Outputs 3–4  ⌄',348,62,220);
 note(b,'44.1 kHz input → 48 kHz output · Rate conversion',28,184,520);
 const levels=box(b,'MicLine precision meters',24,210,672,174,'#101216',16);
 meter(levels,'INPUT',10,stopped?-90:-23.4,stopped?-90:-13.2,stopped?-90:-10.8);
 meter(levels,'OUTPUT',92,stopped?-90:-17.1,stopped?-90:-7.3,stopped?-90:-6.8);
 const controls=box(b,'Gain and low cut',24,400,672,70);
 text(controls,'Gain',14,12,90);text(controls,'−3.0 dB',198,12,76,13,C.text,true);text(controls,'Reset',278,13,46,11,C.blue);box(controls,'Gain track',14,45,274,4,'#5B616D',2);box(controls,'Gain thumb',176,39,16,16,'#E2E6EF',8);text(controls,'−24',14,55,40,9,C.muted);text(controls,'+12',270,55,40,9,C.muted);
 text(controls,'Low cut',354,12,100);button(controls,'80 Hz  ⌄',354,34,100);text(controls,'Reset',468,44,48,11,C.blue);toggle(controls,'Low cut enabled',606,18);
 text(b,'EFFECTS',26,490,200,11,C.muted,true);text(b,'Bypass effects',550,488,106,12);toggle(b,'Bypass effects off',660,484,false);
 const names=['Noise reduction','Compressor','De-esser','Equalizer'];
 if(!count)note(b,'Add an Audio Unit effect, or process with gain and low cut.',26,523,510);
 for(let i=0;i<visible;i++){const row=box(b,'Effect '+(i+1),24,518+i*56,672,48);for(let dot=0;dot<6;dot++)box(row,'Reorder grip dot',13+(dot%2)*5,16+Math.floor(dot/2)*5,2,2,C.muted,1);text(row,names[i],42,9,270,13,C.text,true);text(row,'Audio Unit',42,28,240,10,C.muted);toggle(row,'Effect enabled',436,14);button(row,'Controls',498,8,100);text(row,'×',638,13,22,20,C.muted);}
 const footer=526+visible*56;
 if(count>4)text(b,`${count} effects`,350,footer+9,100,11,C.muted);
 button(b,'Add Effect…',574,footer,122);
 note(b,'Monitor: Off · Headphones  ⌄',26,footer+9,310);
 return b;
}
main('Main · 2 effects · channel routing',0,2);
main('Main · no effects · stopped',780,0,true);
main('Main · 6 effects · bounded list',1560,6);
const menu=board('Menu bar · useful quick controls',2340,0,340,430);text(menu,'MicLine',18,18,280,14,C.text,true);
text(menu,'● Processing',18,64,220,14,C.green,true);note(menu,'Studio Interface · Input 2',18,91,300);note(menu,'Virtual Cable · Outputs 3–4',18,112,300);
box(menu,'Output level',18,148,304,8,'#30343C',4);box(menu,'Current output',18,148,236,8,C.green,4);text(menu,'Output −17.1 dBFS',18,167,280,11,C.muted);
button(menu,'Stop Processing',18,197,304,true);button(menu,'Bypass Effects',18,239,146);button(menu,'Monitor…',176,239,146);
button(menu,'Open MicLine',18,291,304);button(menu,'Settings…',18,333,146);button(menu,'Quit',176,333,146);note(menu,'Monitor is off · 2 effects enabled',18,387,304);
function setup(name,x,state){const b=board(name,x,930,620,660);title(b,'Set up MicLine');
 text(b,'Set up your microphone',28,74,550,24,C.text,true);note(b,'Choose where processed audio goes. You can finish setup later.',28,114,550);
 const mic=box(b,'Microphone permission',28,160,564,112);text(mic,'1   Allow microphone access',16,16,530,15,C.text,true);
 note(mic,state==='denied'?'Access is off. Enable MicLine in macOS Microphone settings.':state==='ready'?'Microphone access is allowed. Processing is still stopped.':'macOS will ask for permission. No recording is saved.',16,47,528);
 button(mic,state==='denied'?'Open Privacy Settings…':state==='ready'?'Allowed':'Allow Microphone…',16,74,204,state==='new');
 const route=box(b,'Choose output without vendor lock-in',28,290,564,186);text(route,'2   Choose your audio route',16,16,530,15,C.text,true);
 button(route,'Microphone: Studio Interface  ⌄',16,47,530);button(route,state==='ready'?'Output: Virtual Cable  ⌄':'Choose any installed output…  ⌄',16,89,530);
 note(route,'Already use a virtual device? Select it here. For speakers or\nheadphones, MicLine asks for confirmation before playing audio.',16,136,530);
 text(b,'Need a virtual microphone?',30,501,500,14,C.text,true);note(b,'BlackHole 2ch is one option for sending audio to call apps.',30,528,548);button(b,'BlackHole setup guide…',30,554,220);
 button(b,'Set Up Later',28,606,140);button(b,state==='ready'?'Finish Setup':'Continue when ready',382,606,210,state==='ready');return b;}
setup('Onboarding · request permission',0,'new');setup('Onboarding · denied recovery',680,'denied');setup('Onboarding · alternative device ready',1360,'ready');
const help=board('Optional BlackHole guide · recovery',2040,930,640,660);title(help,'Virtual microphone setup');
text(help,'Install BlackHole 2ch',28,76,570,24,C.text,true);note(help,'Already have a virtual device? Go back and select it instead.',28,115,570);
text(help,'1   Download from the developer',28,165,570,15,C.text,true);button(help,'Open BlackHole Download…',28,195,270);
text(help,'2   Close call and audio apps, then run the installer',28,252,570,15,C.text,true);note(help,'Save any recording first. MicLine does not install a driver for you.',28,281,570);
text(help,'3   Check for the new device',28,335,570,15,C.text,true);button(help,'Check Again',28,369,150);note(help,'No device detected yet',196,378,380);
const recover=box(help,'Audio reload confirmation',28,425,584,134);text(recover,'Try without restarting your Mac',16,14,550,15,C.text,true);
note(recover,'Quit audio apps, then restart the macOS audio service. This\ninterrupts all audio and may require administrator approval.',16,44,550);button(recover,'Show Audio Restart Steps…',16,90,260);
note(help,'Check again afterward. If it still does not appear, follow the\ninstaller’s restart request. A no-reboot recovery is not guaranteed.',28,578,584);
const states=board('Meter states · precision and finish',0,1660,720,690);title(states,'MicLine meter specification');
meter(states,'QUIET',66,-37.4,-24.1,-22.6,false,688);meter(states,'HEADROOM',151,-17.8,-12.1,-10.5,false,688);meter(states,'HOT',236,-7.4,-2.2,-1.5,false,688);meter(states,'CLIPPED',321,-5.4,0.2,0.2,true,688);meter(states,'STOPPED',406,-90,-90,-90,false,688);
note(states,'RMS fill · white sample-peak marker · coloured peak hold\nGreen below −18 dBFS · amber −18 to −9 · red at/above −9\nCLIP only when a sample reaches 0 dBFS; red alone is not clipping.\n18 pt capsule, subtle static sheen, no decorative level animation.\nSolid fallback with Reduce Transparency; units and values stay visible.\nMeter timing and calibration remain measured DSP behavior.',28,504,664);
const sizing=board('Window behavior · implementation contract',780,1660,720,420);title(sizing,'Window sizing');
text(sizing,'A compact window that follows the chain.',28,78,664,22,C.text,true);
note(sizing,'720 pt content width; no horizontal resizing.\nHeight follows the effects: 574 + 56 × visible rows.\nShow at most four rows before scrolling the effect list.\nCap height to the available screen; reduce visible rows on small screens.\nEmpty, two-effect and six-effect layouts are shown above.\nKeep route, meters and Start/Stop visible as the list scrolls.\nNo full-screen expansion or unbounded empty canvas.\nUse native minimum sizing if larger text cannot fit the nominal width.',28,132,660);
return {page:page.id,artboards:page.children.map(n=>({id:n.id,name:n.name,width:n.width,height:n.height}))};
