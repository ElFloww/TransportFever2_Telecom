// Dependency-free Chrome DevTools smoke test. Use a generated HTML fixture.
import {spawn} from 'node:child_process';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';

const file = resolve(process.argv[2]);
const directory = dirname(file);
const profile = await mkdtemp(join(directory, 'telecom-chrome-'));
const chrome = process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
let browser, socket;
try {
  browser = spawn(chrome, ['--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'],
    {stdio:['ignore','ignore','pipe']});
  const url = await new Promise((resolve, reject) => {
    let stderr = '';
    const timer = setTimeout(() => reject(new Error('Chrome startup timed out')), 20000);
    browser.once('error', error => {clearTimeout(timer);reject(error);});
    browser.stderr.on('data', chunk => {
      stderr += chunk;
      const match = stderr.match(/DevTools listening on (ws:\/\/\S+)/);
      if(match){clearTimeout(timer);resolve(match[1]);}
    });
    browser.once('exit', () => {clearTimeout(timer);reject(new Error(stderr));});
  });
  socket = new WebSocket(url);
  await new Promise((resolve,reject) => {socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
  let nextId = 0;
  const pending = new Map(), listeners = [], errors = [], requests = [];
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if(pending.has(message.id)) {
      const entry = pending.get(message.id); pending.delete(message.id);clearTimeout(entry.timer);
      message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result);
    }
    if(message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails);
    if(message.method === 'Network.requestWillBeSent') requests.push(message.params.request.url);
    for(const listener of [...listeners]) listener(message);
  });
  function call(method, params = {}, sessionId) {
    const id = ++nextId;
    return new Promise((resolve,reject) => {
      const timer = setTimeout(() => {pending.delete(id);reject(new Error(`CDP timeout: ${method}`));}, 20000);
      pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params,sessionId}));
    });
  }
  const target = await call('Target.createTarget', {url:'about:blank'});
  const {sessionId} = await call('Target.attachToTarget',{targetId:target.targetId,flatten:true});
  const page = (method,params) => call(method,params,sessionId);
  async function evaluate(expression) {
    const response = await page('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});
    if(response.exceptionDetails) throw new Error(response.exceptionDetails.exception?.description || response.exceptionDetails.text);
    return response.result.value;
  }
  await page('Page.enable');await page('Runtime.enable');await page('Network.enable');
  await page('Emulation.setDeviceMetricsOverride',{width:1280,height:900,deviceScaleFactor:1,mobile:false});
  const loaded = new Promise((resolve,reject) => {
    const timer = setTimeout(() => reject(new Error('Page load timed out')), 20000);
    const listener = message => {
      if(message.sessionId===sessionId && message.method==='Page.loadEventFired'){
        clearTimeout(timer);listeners.splice(listeners.indexOf(listener),1);resolve();
      }
    };listeners.push(listener);
  });
  await page('Page.navigate',{url:pathToFileURL(file).href});await loaded;
  const terrain = await evaluate(`new Promise((resolve,reject) => {
    const source=document.querySelector('#terrain image');
    if(!source)return reject(new Error('embedded terrain missing'));
    const image=new Image();image.onload=()=>resolve({width:image.naturalWidth,height:image.naturalHeight});
    image.onerror=()=>reject(new Error('embedded BMP could not be decoded'));image.src=source.href.baseVal;
  })`);
  assert.deepEqual(terrain,{width:128,height:64},'terrain image aspect ratio or resolution changed');
  await evaluate(`(() => {
    const check = (ok, message) => {if(!ok)throw new Error(message);};
    const map = document.getElementById('map');
    check(map && map.getBoundingClientRect().width > 500,'map not rendered');
    check(document.querySelectorAll('.entity').length===6,'missing equipment or town');
    check(!window.__telecomInjected,'savegame name executed as script');
    check(!document.querySelector('img[onerror]'),'unsafe name became markup');
    const initial=map.viewBox.baseVal.width;
    document.getElementById('zoom-in').click();check(map.viewBox.baseVal.width<initial,'zoom failed');
    document.getElementById('fit').click();check(map.viewBox.baseVal.width===initial,'fit failed');
    const nra=document.querySelector('[data-filter="kind:NRA"]');nra.checked=false;nra.dispatchEvent(new Event('change'));
    check(document.getElementById('node-1').classList.contains('is-hidden'),'kind filter failed');
    nra.checked=true;nra.dispatchEvent(new Event('change'));
    const choose=document.getElementById('choose');choose.value='node-3';choose.dispatchEvent(new Event('change'));
    check(!document.getElementById('detail-node-3').hidden,'selection details missing');
    const only=document.getElementById('only-selected');only.checked=true;only.dispatchEvent(new Event('change'));
    check(document.querySelectorAll('.coverage:not(.is-hidden)').length===2,'selected coverage count wrong');
    const tech=document.querySelector('[data-filter="tech:tech_5g"]');tech.checked=false;tech.dispatchEvent(new Event('change'));
    check(document.querySelectorAll('.coverage:not(.is-hidden)').length===1,'technology filter failed');
    const opacity=document.getElementById('opacity');opacity.value=40;opacity.dispatchEvent(new Event('input'));
    check(getComputedStyle(document.querySelector('.coverage')).fillOpacity==='0.4','opacity failed');
    document.getElementById('centre-selected').click();check(map.viewBox.baseVal.width<=initial/4,'selection centering failed');
    tech.checked=true;tech.dispatchEvent(new Event('change'));only.checked=false;only.dispatchEvent(new Event('change'));
    document.getElementById('fit').click();
  })()`);
  const dragStart = await evaluate(`(() => {
    document.getElementById('zoom-in').click();
    const svg=document.getElementById('map'), rect=svg.getBoundingClientRect();
    return {x:rect.x+rect.width/2,y:rect.y+rect.height/2,viewX:svg.viewBox.baseVal.x,selected:document.getElementById('choose').value};
  })()`);
  await page('Input.dispatchMouseEvent',{type:'mouseMoved',x:dragStart.x,y:dragStart.y});
  await page('Input.dispatchMouseEvent',{type:'mousePressed',x:dragStart.x,y:dragStart.y,button:'left',clickCount:1});
  await page('Input.dispatchMouseEvent',{type:'mouseMoved',x:dragStart.x+70,y:dragStart.y+30,button:'left',buttons:1});
  await page('Input.dispatchMouseEvent',{type:'mouseReleased',x:dragStart.x+70,y:dragStart.y+30,button:'left',clickCount:1});
  const dragEnd = await evaluate(`({viewX:document.getElementById('map').viewBox.baseVal.x,selected:document.getElementById('choose').value})`);
  assert.notEqual(dragEnd.viewX,dragStart.viewX,'drag did not pan');
  assert.equal(dragEnd.selected,dragStart.selected,'drag changed selection');
  await evaluate(`document.getElementById('fit').click()`);
  const desktop = await page('Page.captureScreenshot',{format:'png'});
  await writeFile(join(directory,'telecom-export-desktop.png'),Buffer.from(desktop.data,'base64'));
  await page('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
  await evaluate(`new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))`);
  const mobile = await evaluate(`({width:document.documentElement.scrollWidth,viewport:innerWidth,mapHeight:document.getElementById('map').getBoundingClientRect().height})`);
  assert(mobile.width<=mobile.viewport+1,'mobile layout overflows horizontally');
  assert(mobile.mapHeight>=250,'mobile map collapsed');
  const shot = await page('Page.captureScreenshot',{format:'png'});
  await writeFile(join(directory,'telecom-export-mobile.png'),Buffer.from(shot.data,'base64'));
  assert.equal(errors.length,0,JSON.stringify(errors));
  assert(!requests.some(url=>/^https?:/.test(url)),'offline map made an external request');
  console.log('Chrome smoke passed: desktop/mobile, zoom, drag, filters, selection, opacity, escaping, offline loading.');
} finally {
  if(socket)socket.close();
  if(browser?.pid && browser.exitCode===null){
    const exited=new Promise(resolve=>browser.once('exit',resolve));browser.kill('SIGTERM');
    const timer=setTimeout(()=>browser.kill('SIGKILL'),5000);await exited;clearTimeout(timer);
  }
  await rm(profile,{recursive:true,force:true});
}
