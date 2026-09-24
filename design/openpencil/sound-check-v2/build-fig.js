// Run against the original FIG with OpenPencil eval --stdin -o <candidate.fig>.
// Original artboards are preserved; this page is a proposal, not runtime evidence.
await figma.loadFontAsync({family:'Inter',style:'Regular'});
await figma.loadFontAsync({family:'Inter',style:'Bold'});
let page = figma.createPage(); page.name = 'Sound Check · Journey'; figma.currentPage = page;
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

const flow=[
  {
    "id": "welcome",
    "chapter": 0,
    "title": "A little sound check.",
    "body": "We’ll help your voice come through clearly. You can skip any lesson.",
    "control": "welcome",
    "primary": "Set up my mic",
    "next": "permission",
    "lesson": "See what we’ll do",
    "secondary": [
      "I know my setup",
      "main"
    ]
  },
  {
    "id": "permission",
    "chapter": 0,
    "title": "First, let MicLine listen.",
    "body": "Microphone access lets us check your level. Nothing starts until you choose it.",
    "control": "permission",
    "primary": "Allow microphone",
    "next": "mic",
    "lesson": "Why we ask",
    "secondary": [
      "Set up later",
      "main"
    ],
    "branch": [
      "Permission denied",
      "denied"
    ]
  },
  {
    "id": "mic",
    "chapter": 0,
    "title": "Which mic is yours?",
    "body": "Choose the microphone you speak into. The output comes later.",
    "control": "mic",
    "primary": "Use this microphone",
    "next": "listen",
    "lesson": "Find your microphone",
    "secondary": [
      "Set up later",
      "main"
    ]
  },
  {
    "id": "listen",
    "chapter": 0,
    "title": "Try your everyday voice.",
    "body": "Say a sentence as if you’re talking to a friend.",
    "control": "idle",
    "primary": "Start sound check",
    "next": "gain",
    "lesson": "Watch a level check",
    "secondary": [
      "Skip sound check",
      "noise"
    ],
    "detail": "Input only. No effects, output or recording."
  },
  {
    "id": "gain",
    "chapter": 0,
    "title": "Leave a little headroom.",
    "body": "Now try the loudest voice you expect to use.",
    "control": "meter",
    "primary": "This level works",
    "next": "noise",
    "lesson": "Understand the peak marker",
    "secondary": [
      "Stop and continue",
      "noise"
    ],
    "branch": [
      "Input clipped",
      "clipped"
    ],
    "extra": [
      "No signal",
      "silent"
    ],
    "detail": "LISTENING · Raw input · Stop ends this check"
  },
  {
    "id": "noise",
    "chapter": 1,
    "title": "Less room. More you.",
    "body": "Try Apple’s Sound Isolation to soften background noise.",
    "control": "isolation",
    "primary": "Preview sound isolation",
    "next": "audition",
    "lesson": "Find Apple’s sound isolation",
    "clip": "find-isolation",
    "secondary": [
      "Keep my natural sound",
      "compressor"
    ],
    "branch": [
      "Effect unavailable",
      "unavailable"
    ]
  },
  {
    "id": "audition",
    "chapter": 1,
    "title": "Listen through headphones.",
    "body": "Choose headphones before hearing your processed voice.",
    "control": "headphones",
    "primary": "Use these headphones",
    "next": "compare",
    "lesson": "Compare without feedback",
    "secondary": [
      "Skip listening",
      "compressor"
    ]
  },
  {
    "id": "compare",
    "chapter": 1,
    "title": "Keep the version you prefer.",
    "body": "Speak, then pause. Switch between the two and listen for a natural voice.",
    "control": "compare",
    "primary": "Keep sound isolation",
    "next": "compressor",
    "lesson": "Find Apple’s sound isolation",
    "clip": "find-isolation",
    "secondary": [
      "Undo this effect",
      "compressor"
    ],
    "detail": "HEADPHONE PREVIEW · Nothing sent to a call"
  },
  {
    "id": "compressor",
    "chapter": 1,
    "title": "Soften the louder words.",
    "body": "A gentle compressor helps loud and quiet phrases sit closer together.",
    "control": "compressor",
    "primary": "Try gentle compression",
    "next": "compression",
    "lesson": "Find Apple’s compressor",
    "clip": "find-compressor",
    "secondary": [
      "Skip compression",
      "output"
    ]
  },
  {
    "id": "compression",
    "chapter": 1,
    "title": "Still sounds like you?",
    "body": "Try a quiet sentence, then a louder one. Keep it only if you prefer it.",
    "control": "compression",
    "primary": "Keep this sound",
    "next": "output",
    "lesson": "Find Apple’s compressor",
    "clip": "find-compressor",
    "secondary": [
      "Undo compression",
      "output"
    ],
    "detail": "HEADPHONE PREVIEW · Recheck output peaks"
  },
  {
    "id": "output",
    "chapter": 2,
    "title": "Where should your voice go?",
    "body": "A virtual audio device carries your processed voice into other apps.",
    "control": "output",
    "primary": "Use this output",
    "next": "handoff",
    "lesson": "Connect your call app",
    "secondary": [
      "Finish this later",
      "main"
    ],
    "branch": [
      "No virtual device",
      "driver"
    ]
  },
  {
    "id": "handoff",
    "chapter": 2,
    "title": "One last choice in your app.",
    "body": "In your call app’s microphone menu, choose Studio Cable.",
    "control": "handoff",
    "primary": "Start output check",
    "next": "verify",
    "lesson": "Find the microphone menu",
    "secondary": [
      "Finish this later",
      "main"
    ]
  },
  {
    "id": "verify",
    "chapter": 2,
    "title": "Check the other end.",
    "body": "Speak and look for a moving input meter in your call app.",
    "control": "verify",
    "primary": "I see my voice there",
    "next": "ready",
    "lesson": "Check the receiving app",
    "secondary": [
      "I don’t see a signal",
      "receiving"
    ],
    "detail": "OUTPUT CHECK · Studio Cable · Stop available"
  },
  {
    "id": "ready",
    "chapter": 2,
    "title": "Your mic is set up.",
    "body": "You confirmed the signal in your app. Your sound check is saved.",
    "control": "ready",
    "primary": "Open MicLine",
    "next": "main",
    "lesson": "Your everyday controls",
    "secondary": [
      "Review my setup",
      "mic"
    ]
  },
  {
    "id": "main",
    "chapter": 2,
    "title": "Ready when you are.",
    "body": "Start processing when you want to use this sound.",
    "control": "main",
    "primary": "Run sound check again",
    "next": "welcome",
    "lesson": "Small tips, when you need them",
    "secondary": [
      "Show a gain tip",
      "tip"
    ]
  },
  {
    "id": "denied",
    "chapter": 0,
    "title": "Access is still off.",
    "body": "Enable MicLine in Privacy & Security → Microphone, then come back.",
    "control": "denied",
    "primary": "I’ve enabled access",
    "next": "mic",
    "lesson": "Enable microphone access",
    "secondary": [
      "Set up later",
      "main"
    ]
  },
  {
    "id": "silent",
    "chapter": 0,
    "title": "We haven’t heard anything yet.",
    "body": "Check the mic’s mute switch, then try another input channel.",
    "control": "silent",
    "primary": "Try again",
    "next": "gain",
    "lesson": "Find the right input channel",
    "secondary": [
      "Choose another mic",
      "mic"
    ]
  },
  {
    "id": "clipped",
    "chapter": 0,
    "title": "A little too loud at the mic.",
    "body": "Lower the gain on your microphone or interface, then try again.",
    "control": "clipped",
    "primary": "Check again",
    "next": "gain",
    "lesson": "Hardware gain versus trim",
    "secondary": [
      "My mic has no gain knob",
      "position"
    ]
  },
  {
    "id": "position",
    "chapter": 0,
    "title": "Give your mic some space.",
    "body": "Move a little farther away and speak normally. MicLine’s trim cannot repair input clipping.",
    "control": "position",
    "primary": "Check again",
    "next": "gain",
    "lesson": "Adjust your mic position",
    "secondary": [
      "Skip this check",
      "noise"
    ]
  },
  {
    "id": "unavailable",
    "chapter": 1,
    "title": "We can skip this effect.",
    "body": "Sound isolation isn’t available on this setup. Your microphone still works.",
    "control": "unavailable",
    "primary": "Continue without it",
    "next": "compressor",
    "lesson": "Effects are optional",
    "secondary": [
      "Choose an installed AU",
      "library"
    ]
  },
  {
    "id": "library",
    "chapter": 1,
    "title": "Use an effect you trust.",
    "body": "Installed Audio Units can offer another noise-reduction option.",
    "control": "library",
    "primary": "Continue without adding",
    "next": "compressor",
    "lesson": "Find an Audio Unit",
    "clip": "find-isolation",
    "secondary": [
      "Back to sound isolation",
      "noise"
    ]
  },
  {
    "id": "driver",
    "chapter": 2,
    "title": "Need a virtual microphone?",
    "body": "BlackHole is one option. Already have another? You can use that instead.",
    "control": "driver",
    "primary": "Show installation steps",
    "next": "install",
    "lesson": "Set up a virtual device",
    "secondary": [
      "Choose an existing device",
      "output"
    ]
  },
  {
    "id": "install",
    "chapter": 2,
    "title": "Install, then check again.",
    "body": "Get BlackHole from its official site. Finish its installer, then return here.",
    "control": "install",
    "primary": "Check for new devices",
    "next": "output",
    "lesson": "Return after installation",
    "secondary": [
      "It still isn’t showing",
      "rescan"
    ]
  },
  {
    "id": "rescan",
    "chapter": 2,
    "title": "The device hasn’t appeared.",
    "body": "Close audio apps before trying a macOS audio-service restart.",
    "control": "rescan",
    "primary": "Show restart guidance",
    "next": "restart",
    "lesson": "Recover without guessing",
    "secondary": [
      "Leave this for later",
      "main"
    ]
  },
  {
    "id": "restart",
    "chapter": 2,
    "title": "This interrupts all audio.",
    "body": "Save recordings and close calls first. Restarting audio may need administrator approval.",
    "control": "restart",
    "primary": "I’ve restarted audio · Check again",
    "next": "output",
    "lesson": "Restart guidance",
    "secondary": [
      "Use the installer’s restart advice",
      "main"
    ]
  },
  {
    "id": "receiving",
    "chapter": 2,
    "title": "Let’s check the connection.",
    "body": "Keep MicLine processing, then select Studio Cable as your call app’s microphone.",
    "control": "receiving",
    "primary": "Try the output check again",
    "next": "verify",
    "lesson": "Trace the signal",
    "secondary": [
      "Choose another output",
      "output"
    ]
  },
  {
    "id": "disconnected",
    "chapter": 0,
    "title": "Your microphone disconnected.",
    "body": "We stopped the sound check. Reconnect it or choose another microphone.",
    "control": "disconnected",
    "primary": "Choose a microphone",
    "next": "mic",
    "lesson": "Resume safely",
    "secondary": [
      "End sound check",
      "main"
    ]
  },
  {
    "id": "resume",
    "chapter": 0,
    "title": "Pick up where you left off.",
    "body": "Your choices are saved. Listening is off until you start it again.",
    "control": "resume",
    "primary": "Resume sound check",
    "next": "listen",
    "lesson": "You’re in control",
    "secondary": [
      "Start over",
      "welcome"
    ]
  },
  {
    "id": "tip",
    "chapter": 2,
    "title": "Gain changes what enters effects.",
    "body": "It makes your signal louder or quieter. Lower hardware gain if the raw input clips.",
    "control": "tip",
    "primary": "Got it",
    "next": "main",
    "lesson": "See the difference",
    "secondary": [
      "Open sound check",
      "listen"
    ]
  }
]
;

const results=[];
for(let i=0;i<flow.length;i++){
 if(i===15){page=figma.createPage();page.name='Sound Check · Recovery';figma.currentPage=page;}
 const s=flow[i],j=i<15?i:i-15;
 const scene=board(s.id+' · '+s.title,(j%3)*1080,Math.floor(j/3)*660,1000,600);scene.fills=paint('#18191C');scene.cornerRadius=0;scene.strokes=[];
 const w=box(scene,'Focused setup window',24,32,600,520,C.bg,19);text(w,'Sound Check',24,20,350,14,C.text,true);text(w,'Set Up Later',490,20,95,11,C.muted);
 text(w,['Microphone · 1 of 3','Sound · 2 of 3','Output · 3 of 3'][s.chapter],24,70,540,12,C.muted);
 box(w,'Native separator',24,101,552,1,C.line,0);
 text(w,s.title,24,124,552,22,C.text,true);text(w,s.body,24,183,552,13,C.muted);
 const c=box(w,'One task at a time',24,251,552,116,'#17191D',13);
 const label={welcome:'Find your level  →  Shape your sound  →  Use it',permission:'Microphone access · Requested when you choose Allow',mic:'Studio Microphone     ⌄                       Input 1 · Mono',listen:'Studio Microphone · Ready to listen',noise:'Apple Sound Isolation                                  Optional',audition:'Studio Headphones     ⌄',compare:'Original                 |                 Processed',compressor:'Gentle compression · Apple AUDynamicsProcessor',compression:'Original                 |                 Processed',output:'Studio Cable     ⌄',handoff:'MicLine  →  Studio Cable  →  Your call app',verify:'Look for your voice in the receiving app',ready:'✓  Your choices are saved · Output check ends',main:'Studio Microphone → Studio Cable · Stopped',denied:'Microphone access is off',silent:'Mute switch checked?       Input 1 / Input 2',position:'Move a little farther from the microphone',unavailable:'Continue without noise reduction',library:'Choose an installed Audio Unit',driver:'BlackHole · External installer',install:'Open the official BlackHole site ↗',rescan:'No new device detected',restart:'Save recordings. Close calls. Manual recovery only.',receiving:'MicLine running? → Correct microphone selected?',disconnected:'Listening stopped · Device unavailable',resume:'Level check saved · Listening off',tip:'Gain · 0.0 dB · Explanation beside the control'}[s.id];
 if(s.id==='gain'||s.id==='clipped'){
 text(c,'RAW INPUT',16,12,230,10,C.muted);text(c,s.id==='clipped'?'CLIP  +0.2 dBFS':'−12.3 dBFS',344,10,175,18,s.id==='clipped'?C.red:C.green,true);
 const track=box(c,'Live level track',16,43,504,20,'#344339',10);box(track,'Example fill',0,0,s.id==='clipped'?504:394,20,s.id==='clipped'?C.red:C.green,10);box(track,'Sample peak',s.id==='clipped'?500:430,1,2,18,'#FFFFFF',1);
 text(c,s.id==='clipped'?'Lower gain at your microphone.':'Room for louder words in this example.',16,76,500,11,C.muted);
 }else text(c,label||'Optional step',18,33,500,14,C.text,true);
 if(s.detail)text(w,s.detail,24,395,552,11,C.muted);
 box(w,'Footer divider',0,452,600,1,C.line,0);text(w,'Back',24,479,52,12,C.muted);text(w,s.secondary?.[0]||'',86,477,228,11,C.muted);button(w,s.primary,326,468,252,true);
 const pip=box(scene,'Companion lesson',648,228,328,284,'#292B30',17);text(pip,'Quick Guide',16,14,220,9,C.muted);text(pip,'×',297,10,20,15,C.muted);
 const screen=box(pip,'Demonstration surface',0,36,328,132,'#202124',0);
 if(s.clip){text(screen,'Add Audio Unit Effect',12,12,305,12,C.text,true);const search=box(screen,'Recorded search field',12,37,304,28,'#34373D',6);text(search,s.clip==='find-isolation'?'AUSoundIsolation':'Dynamics',8,7,288,11,C.text);text(screen,s.clip==='find-isolation'?'AUSoundIsolation':'AUDynamicsProcessor',22,83,230,12,C.text);text(screen,'Add',268,84,42,11,C.muted);}
 else{[20,34,50,62,40,54,29].forEach((h,k)=>box(screen,'Lesson motif',117+k*13,60-h/2,7,h,C.blue,4));text(screen,'Lesson storyboard',101,103,160,10,C.muted);}
 text(pip,s.lesson,16,185,296,14,C.text,true);text(pip,s.clip?'▶  Planned recording · '+(s.clip==='find-isolation'?'10':'8')+' sec':'Watch the example · planned clip',16,222,296,11,C.blue);text(pip,'Read the steps',16,249,240,11,C.muted);
 text(scene,'DESIGN PROPOSAL · '+s.id+' → '+s.next,24,566,940,11,C.muted);
 results.push({id:scene.id,name:scene.name,page:page.id});
}
return results;
