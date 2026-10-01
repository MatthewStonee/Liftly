"""Original 24-second instrumental, synthesized locally; no sampled recordings."""
from pathlib import Path
import numpy as np
import wave
ROOT = Path(__file__).resolve().parents[1]
SR = 48000
DUR = 24.0
rng = np.random.default_rng(29)
out = np.zeros((int(SR * DUR), 2), dtype=np.float64)
def add(signal, start, gain=1., pan=0.):
    i = int(start * SR)
    n = min(len(signal), len(out)-i)
    if n <= 0: return
    out[i:i+n, 0] += signal[:n] * gain * np.sqrt((1-pan)/2)
    out[i:i+n, 1] += signal[:n] * gain * np.sqrt((1+pan)/2)
def freq(m): return 440*2**((m-69)/12)
# Soft, detuned chord bed; four-bar harmonic movement.
chords = [[50,57,60,65], [46,53,57,62], [53,60,64,69], [48,55,59,64]]
for bar in range(12):
    notes = chords[bar%4]
    t = np.arange(int(2.5*SR))/SR
    env = np.minimum(t/.25,1)*np.minimum((2.5-t)/.65,1)
    pad = sum(np.sin(2*np.pi*freq(m)*t)+.2*np.sin(2*np.pi*freq(m)*1.003*t) for m in notes)/5
    add(pad*env, bar*2, .095, (-1)**bar*.18)
    # Plucked, sparse arpeggio.
    for k,m in enumerate([notes[0]+12,notes[2]+12,notes[1]+12,notes[3]+12]):
        start=bar*2+k*.5+.25
        t=np.arange(int(.8*SR))/SR
        pluck=(np.sin(2*np.pi*freq(m)*t)+.18*np.sin(2*np.pi*freq(m)*2*t))*np.exp(-t*7)*np.minimum(t/.005,1)
        add(pluck,start,.12,(-1)**k*.38)
        add(pluck,start+.25,.028,(-1)**(k+1)*.6)
for beat in range(48):
    start=beat*.5
    t=np.arange(int(.33*SR))/SR
    # Descending sine kick, tiny transient, no clipping.
    kick=np.sin(2*np.pi*(47*t+56*.023*(1-np.exp(-t/.023))))*np.exp(-t*14)
    add(kick,start,.40)
    if beat%2:
        t=np.arange(int(.15*SR))/SR
        noise=rng.standard_normal(len(t)); noise=np.concatenate(([0],np.diff(noise)))
        clap=noise*np.exp(-t*37)*np.minimum(t/.002,1)
        add(clap,start,.027,.05)
    for h in range(2):
        t=np.arange(int(.055*SR))/SR
        noise=rng.standard_normal(len(t)); noise=np.concatenate(([0],np.diff(noise)))
        add(noise*np.exp(-t*90),start+h*.25,.009 if h==0 else .005,(-1)**h*.35)
    if beat%4 in [0,2]:
        t=np.arange(int(.4*SR))/SR
        m=chords[(beat//4)%4][0]-12
        bass=(np.sin(2*np.pi*freq(m)*t)+.18*np.sin(4*np.pi*freq(m)*t))*np.exp(-t*7)*np.minimum(t/.008,1)
        add(bass,start,.22)
# Gentle air at each scene transition.
for at in [4,9,14,20]:
    t=np.arange(int(.38*SR))/SR
    n=rng.standard_normal(len(t)); smooth=np.convolve(n,np.ones(14)/14,mode='same')
    add(smooth*np.sin(np.pi*t/.38)**2,at-.22,.055,-.15)
time=np.arange(len(out))/SR
out*=np.minimum(time/.25,1)[:,None]*np.minimum((DUR-time)/1.1,1)[:,None]
out=np.tanh(out*1.4)
out*=.86/max(1.,np.max(np.abs(out)))
with wave.open(str(ROOT/'assets/original-score.wav'),'wb') as f:
    f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR)
    f.writeframes((out*32767).astype('<i2').tobytes())
print('Original score:', len(out)/SR, 'seconds; peak',float(np.max(abs(out))))
