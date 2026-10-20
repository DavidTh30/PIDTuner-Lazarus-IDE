# Math 01 — PID Tuning Explorer

> ชื่อโปรเจกต์: **PID Tuning Explorer** (ตัวสำรวจการจูน PID แบบ interactive)
> แหล่งที่มา: ภาพ 2 ภาพจากวิดีโอสอน (สไตล์แอนิเมชันคณิตศาสตร์แบบ Manim / 3Blue1Brown)
> วันที่วิเคราะห์: 2026-10-21

## ไฟล์ในโฟลเดอร์

| ไฟล์ | เนื้อหา |
|---|---|
| `images/pid_equation.png` | ภาพที่ 1 — สมการ PID แยกสีแต่ละเทอม |
| `images/pid_tuning_heatmap.png` | ภาพที่ 2 — สมการ + หน้าปัด 3 ตัว + heatmap ของ Kp × Kd |
| `README.md` | เอกสารวิเคราะห์นี้ |
| `PIDTuner.lpi` / `PIDTuner.lpr` | โปรเจกต์ Lazarus (ต้องใช้ BGRABitmapPack) → `bin\PIDTuner.exe` |
| `src/PIDCore.pas` | คณิตศาสตร์ล้วน — PID, plant จำลอง, step response, วัดผล, sweep grid, colormap |
| `src/BGRAView.pas` | คลาสฐาน `TBGRAView` (วาดลง TBGRABitmap) + helper สี/สัญลักษณ์ K ห้อย |
| `src/KnobControl.pas` | `TKnob` — หน้าปัด 270° ลากเมาส์ขึ้น/ลง (Shift = ละเอียด), ล้อเมาส์ ±1% |
| `src/HeatmapView.pas` | `THeatmap` — grid Kp × Kd, คลิก/ลากเลือกช่อง, hover แสดงค่า |
| `src/PlotViews.pas` | `TEquationView` (สมการสี) + `TResponsePlot` (กราฟ step response + ITAE/overshoot/settle) |
| `src/uMainForm.pas` | หน้าต่างหลัก (สร้าง UI ในโค้ด ไม่มี .lfm) เชื่อมทุกส่วนเข้ากับ PIDCore |

### Build / Run

```
C:\lazarus\lazbuild.exe PIDTuner.lpi
bin\PIDTuner.exe
bin\PIDTuner.exe --snapshot out.png [Kp Ki Kd]   ← render ทั้งหน้าต่างเป็น PNG โดยไม่เปิดหน้าต่าง
bin\PIDTuner.exe --gif out.gif [frames]          ← GIF ตัวอย่าง: Ki กวาด 0 → 6 → 0 (100 ms/เฟรม)
```

### Capture PNG / GIF (`src/CaptureKit.pas`, `src/FlatButton.pas`)
- ปุ่ม **PNG** (มุมขวาบน) หรือ **Ctrl+S** → บันทึกภาพเต็มขนาดของหน้าต่าง
- ปุ่ม **GIF** หรือ **Ctrl+G** → เริ่มอัด (ปุ่มเป็นสีแดง "Stop") กดอีกครั้งเพื่อหยุด หยุดเองที่ 60 วินาที
- ไฟล์อยู่ที่ `bin\captures\pid_yyyymmdd_hhnnss.png / .gif` ไม่รวมปุ่ม capture ในภาพ
- GIF: 12 fps, ย่อ 50 %, วนซ้ำไม่สิ้นสุด
- ปรับได้ที่ต้น `uMainForm.pas`: `GifFps`, `GifScale`, `GifMaxSeconds`

`TGifRecorder` (`src/CaptureKit.pas`, ใช้ร่วมกันทั้ง 2 โปรแกรม):
- เขียน GIF ลงไฟล์ทีละเฟรมระหว่างอัด (ไม่เก็บทุกเฟรมไว้ในหน่วยความจำ) หยุดแล้วบันทึกเสร็จทันที
- เขียนเฉพาะสี่เหลี่ยมที่เปลี่ยนจากเฟรมก่อน, เฟรมที่ไม่เปลี่ยนเลยจะยืดเวลาเฟรมเดิม
- ลดสีเหลือ ≤ 256 สีต่อเฟรมเอง (histogram 15 บิต + สีที่ใช้บ่อยสุด, ไม่ dithering) แล้วใช้ `GIFEncodeLZW` ของ BGRABitmap
- ย่อ/ลดสี/บีบอัดทำใน worker thread — ลูป vsync แค่คัดลอกเฟรม; ถ้า worker ตามไม่ทันจะยืดเฟรมล่าสุดแทน
  (`Realtime := False` สำหรับ headless: รอคิวว่าง ไม่รวมเฟรม)
- เวลาของเฟรมสะสมเศษจาก 1/100 s ไว้ ความยาว GIF จึงตรงกับเวลาที่อัดจริง

การเชื่อมโยง: หมุน Kp/Kd → ช่องที่เลือกใน heatmap ย้ายตาม · คลิกช่อง → knob Kp/Kd หมุนไปค่ากลางช่อง ·
หมุน Ki → คำนวณ heatmap ใหม่ทั้งหมด (80 simulation × 10 s) · กราฟ step response อัปเดตทุกครั้ง
ช่วงค่า: Kp 0.5–12, Ki 0–6, Kd 0–7, plant m=1, c=0.5, k=1 (ค่าคงที่อยู่ต้น `uMainForm.pas`)

---

## PID Explainer — โปรแกรมอธิบายตัวแปรทีละตัว (`Explainer\`)

โปรแกรมสอนแบบ interactive 12 หน้า วาดด้วย BGRABitmap ลง `TBGLBitmap` แล้วแสดงผ่าน `TOpenGLControl`
แบบ vsync (`wglSwapIntervalEXT`, ลูปเดียวกับ DottedWave) ออกแบบที่ 1280×760 แล้วย่อ/ขยายพอดีหน้าต่าง

| หน้า | เนื้อหา | การโต้ตอบ |
|---|---|---|
| 1 ภาพรวม | สมการ, block diagram r → Σ → PID → Plant → y ที่สัญญาณไหลจริง | — |
| 2 r y e | setpoint, ค่าที่วัด, error, เครื่องหมาย | จำลองสด, setpoint สลับทุก 4 s |
| 3 Kp | P = Kp·e, offset e∞ = 1/(1+Kp) | slider Kp, เส้นเทียบ Kp 1/4/15 |
| 4 Ki | ∫e dt (พื้นที่แรเงา), ล้าง error ค้าง, windup | slider Ki |
| 5 Kd | ความชัน/เส้นสัมผัส, damping, noise, derivative kick | slider Kd, N = noise |
| 6 u | P + I + D แบ่งงานกัน, saturation | 3 slider + แท่งค่า ณ เวลาปัจจุบัน |
| 7 dt | การสุ่มตัวอย่าง, Σe·dt เทียบ ∫, ผลต่างเทียบอนุพันธ์ + โค้ดจริง | slider dt |
| 8 รถยนต์ | cruise control บนเนิน (แรงโน้มถ่วง = disturbance) | Kp Ki Kd r, G = ลมต้าน |
| 9 เตาอบ | dead time 4 s, saturation 0–100 %, anti-windup | W = เปิด/ปิด anti-windup, G = เปิดประตู |
| 10 โดรน | แรงโน้มถ่วง → ต้องมี Ki, Kd เป็นแดมเปอร์ | G = ลมกดลง |
| 11 โค้ด | วิธีใช้ PIDCore ใน Lazarus + ลูป vsync OpenGL/BGRABitmap | — |
| 12 สรุป | ตารางผลของเกน, วิธีจูนด้วยมือ, Ziegler–Nichols, heatmap Kp × Kd | — |

ปุ่ม: ← → / 1–9, 0 เปลี่ยนหน้า · Space หยุด · R เริ่มหน้าใหม่ · V vsync · F fps · F11 เต็มจอ ·
**Ctrl+S** = PNG · **Ctrl+G** = เริ่ม/หยุดอัด GIF (หรือคลิกปุ่ม PNG / GIF มุมขวาบน)

```
C:\lazarus\lazbuild.exe Explainer\PIDExplainer.lpi
Explainer\bin\PIDExplainer.exe
Explainer\bin\PIDExplainer.exe --snapshot out_dir [seconds]   ← render ทุกหน้าเป็น PNG (ไม่ใช้ OpenGL)
Explainer\bin\PIDExplainer.exe --gif out.gif <page> [seconds] ← อัด GIF ของหน้าเดียวแบบ headless
```

```
Explainer\bin\PIDExplainer.exe --bench out.txt                ← เวลา render ต่อเฟรมของทุกหน้า (ms)
```

ประสิทธิภาพ: ทุกหน้าวิ่ง 60 fps (vsync) รวมทั้งระหว่างอัด GIF — render ใช้ 0.2–5.7 ms ต่อเฟรม
- ข้อความที่วาดทุกเฟรมผ่าน sprite cache (`DrawTextCached` ใน `uDrawKit`): ข้อความเดิมวาดครั้งเดียวแล้ว blend
  (เดิม TextOut ผ่าน LCL font renderer ~0.25 ms/ครั้ง × 20–40 ครั้งต่อเฟรม)
- หน้า replay (Kp, Ki, Kd, u) แยก `DrawStill` (grid, ป้าย, เส้นเทียบ, เส้นจางเต็ม) เก็บเป็น layer
  สร้างใหม่เฉพาะเมื่อ trace เปลี่ยน ทุกเฟรมวาดแค่ `DrawMoving` (เส้นที่กำลังวิ่ง, cursor, ค่าตัวเลข)
- หน้า Kp: จาก 19.3 ms (41 fps) เหลือ 3.1 ms

Capture: PNG 1280×760 เต็มขนาด, GIF 960×570 (75 %) 12 fps สูงสุด 60 วินาที → `Explainer\bin\captures\`
ปุ่มและแถบ fps วาดหลังจับภาพ จึงไม่ติดไปในไฟล์ ข้อความแจ้งผลแสดงที่มุมขวาบน

ไฟล์ใน `Explainer\src`: `uExplainerForm` (OpenGL + vsync), `uExplainer` (หัว/แท็บ/cache layer),
`uLessons` (เนื้อหา 12 หน้า), `uScenarios` (ฟิสิกส์ รถ/เตาอบ/โดรน), `uSimKit` (trace + ring buffer),
`uDrawKit` (ตัดคำภาษาไทย, กราฟ, slider, gauge), `uPlatform` (QueryPerformanceCounter, swap interval)
ใช้ `..\src` ร่วมกับ PIDTuner (PIDCore, BGRAView, PlotViews, HeatmapView)
`TPIDController` เพิ่ม `LastP/LastI/LastD`, `Integral` และ `AntiWindup` สำหรับหน้าอธิบาย

---

## 1. ภาพที่ 1 — สมการควบคุม PID

$$u(t) = K_p\,e(t) + K_i\int e(t)\,dt + K_d\,\frac{de(t)}{dt}$$

| สัญลักษณ์ | ความหมาย | สีในภาพ |
|---|---|---|
| `u` | สัญญาณควบคุม (control output) ที่ส่งไปยังระบบ | ขาว |
| `e` | error = setpoint − ค่าที่วัดได้ | — |
| `Kp·e` | **Proportional** — ตอบสนองตาม error *ตอนนี้* | ส้ม |
| `Ki·∫e dt` | **Integral** — สะสม error *ในอดีต* กำจัด steady-state error | น้ำเงิน |
| `Kd·de/dt` | **Derivative** — ดูแนวโน้ม *อนาคต* ช่วยหน่วง (damping) ลด overshoot | เขียว |

ผลของการเพิ่มค่าแต่ละตัว (กฎทั่วไป):

| เพิ่ม | Rise time | Overshoot | Settling time | Steady-state error | ความเสี่ยง |
|---|---|---|---|---|---|
| Kp | ลดลง | เพิ่ม | เปลี่ยนเล็กน้อย | ลดลง | สั่น / ไม่เสถียร |
| Ki | ลดลง | เพิ่ม | เพิ่ม | **หายไป** | integral windup |
| Kd | เปลี่ยนเล็กน้อย | ลดลง | ลดลง | ไม่มีผล | ขยาย noise |

## 2. ภาพที่ 2 — หน้าปัดเกน + แผนที่ความร้อน (heatmap)

### 2.1 หน้าปัด (dial / knob) 3 ตัว
- วางตรงใต้แต่ละเทอมของสมการ: ส้ม = Kp, น้ำเงิน = Ki, เขียว = Kd
- องค์ประกอบ: วงแหวนนอกสีเทาเข้ม (track) + ส่วนโค้งสี (value arc) เริ่มจากด้านล่างซ้าย หมุนตามเข็มนาฬิกา + วงกลมในขอบสี + เข็มสีขาว + จุดกลางสีขาว
- มุมกวาดประมาณ 270° (ช่องว่างอยู่ด้านล่าง) — สไตล์ knob ของปลั๊กอินเสียง
- ค่าโดยประมาณจากภาพ: **Kp ≈ 30%**, **Ki ≈ 70%**, **Kd ≈ 30%** ของช่วง

### 2.2 Heatmap
- ขนาด **10 คอลัมน์ × 8 แถว**
- แกน X = **Kp** (ป้ายสีส้ม ด้านล่าง), แกน Y = **Kd** (ป้ายสีเขียว ด้านซ้าย, เพิ่มขึ้นด้านบน)
- **Ki ถูกตรึงไว้** ที่ค่าของหน้าปัดน้ำเงิน → heatmap คือ "ภาพตัดขวาง 2 มิติ" ของพื้นที่ 3 มิติ (Kp, Ki, Kd)
- สีของช่อง = คะแนนคุณภาพการตอบสนอง (เช่น 1/ITAE): แดงเลือดหมูเข้ม = แย่/ไม่เสถียร → teal → cyan → เขียวอ่อน → เหลือง → **ทอง = ดีที่สุด**
- ช่องที่เลือก (กรอบทองหนา + เส้นขาวด้านใน) อยู่ที่ **คอลัมน์ 5, แถว 5 จากบน** (index 0-based: x=4, y=4) — คือค่า Kp/Kd ปัจจุบันของหน้าปัด และอยู่ในโซนที่ดีที่สุด
- แถบแดงด้านล่างคือ progress bar ของวิดีโอ (~27%) — ไม่ใช่ส่วนของ UI

ระดับสีโดยประมาณ (0 = แย่สุด … 7 = ดีสุด), แถวบน = Kd สูง:

```
Kd↑  0 0 0 0 0 0 1 1 2 4
     0 0 0 1 1 2 3 4 5 5
     0 0 2 2 4 5 6 6 4 3
     1 2 2 4 6 7 7 5 4 3
     0 2 3 5[7]6 5 4 3 2     ← ช่องที่เลือก
     0 2 4 5 5 4 3 3 2 1
     0 1 3 4 3 3 2 2 1 0
     0 0 0 1 0 0 0 0 0 0
                         Kp→
```

### 2.3 การตีความ
- **Kd ต่ำสุด (แถวล่าง)** → แย่เกือบทั้งแถว: damping ไม่พอ ระบบสั่นหรือไม่เสถียร
- **Kp ต่ำสุด (คอลัมน์ซ้าย)** → แย่: ตอบสนองช้าเกินไป
- **มุมซ้ายบน (Kp ต่ำ, Kd สูง)** → overdamped หนืดเกินไป
- **มุมขวาล่าง (Kp สูง, Kd ต่ำ)** → overshoot / oscillation
- โซนที่ดีเป็น "สันเขา" ทแยงจากกลาง-ล่างไปขวา-บน: **ยิ่ง Kp สูง ยิ่งต้องการ Kd สูงขึ้นเพื่อหน่วง** — ตรงกับทฤษฎี damping ratio ζ ของระบบอันดับสอง

## 3. Design tokens (สีโดยประมาณจากภาพ)

| Token | Hex | ใช้กับ |
|---|---|---|
| `bg` | `#0E1117` | พื้นหลัง |
| `text` | `#FFFFFF` | u, =, +, เข็มหน้าปัด |
| `kp` | `#F0A04B` | ส้ม — Kp |
| `ki` | `#4DA3F0` | น้ำเงิน — Ki |
| `kd` | `#5AD27D` | เขียว — Kd |
| `knob_track` | `#2A2F38` | วงแหวนพื้นของหน้าปัด |
| `knob_face` | `#111820` | หน้าปัดด้านใน |
| `heat_0` | `#3D1E26` | แย่/ไม่เสถียร |
| `heat_1` | `#1E5A5C` | |
| `heat_2` | `#2A9D9A` | |
| `heat_3` | `#2ED3C6` | |
| `heat_4` | `#6CD6A6` | |
| `heat_5` | `#B4CC74` | |
| `heat_6` | `#E3C557` | |
| `heat_7` | `#F5BE45` | ดีที่สุด / กรอบช่องที่เลือก |

ฟอนต์สมการ: Computer Modern italic (LaTeX) — ใน Lazarus อาจใช้ภาพ pre-render หรือฟอนต์ "CMU Serif"

## 4. แผนการพัฒนา (Lazarus + BGRABitmap)

สถาปัตยกรรม:

```
PIDCore.pas      ← คณิตศาสตร์ล้วน (ไม่ขึ้นกับ GUI) — มีแล้วใน src/
  TPIDController   PID แบบ anti-windup + derivative-on-measurement + low-pass
  TPlant           mass-spring-damper  m·x'' + c·x' + k·x = u
  SimulateStep     จำลอง step response → ITAE, overshoot, settling time
  SweepKpKd        คำนวณ grid คะแนน (Ki คงที่)
  HeatColor        แปลงคะแนน 0..1 → สี

KnobControl.pas  ← TKnob (custom control วาดด้วย BGRABitmap, ลากเมาส์/ล้อหมุนเปลี่ยนค่า)
HeatmapView.pas  ← THeatmap (วาด grid, hover/คลิกเลือกช่อง → ตั้งค่า Kp/Kd ของ knob)
EquationView     ← วาดสมการสีตามเทอม
ResponsePlot     ← กราฟ step response ของช่องที่เลือก (เพิ่มเติมจากภาพ)
uMainForm        ← ประกอบทุกอย่าง, คำนวณ sweep ใหม่เมื่อ Ki เปลี่ยน (เร็วพอโดยไม่ต้องใช้ thread)
```

### Checklist
- [x] วิเคราะห์ภาพและบันทึกข้อมูล
- [x] `PIDCore.pas` — PID / plant / metrics / sweep / colormap
- [x] `TKnob` — วาด arc 270°, เข็ม, ลากเมาส์ปรับค่า, event `OnChange`
- [x] `THeatmap` — วาด 10×8 ช่องมุมมน, กรอบเลือก, hover แสดง Kp/Kd/คะแนนใน status bar
- [x] ผูก knob ↔ heatmap (สองทาง): เลือกช่อง → knob Kp/Kd หมุนตาม; หมุน Ki → sweep ใหม่
- [x] กราฟ step response แบบ realtime ของค่าปัจจุบัน
- [x] Capture PNG และอัด GIF (ปุ่ม + Ctrl+S / Ctrl+G + `--gif`)
- [ ] แอนิเมชันเข็ม/สีแบบ easing (สไตล์วิดีโอ)
- [ ] ตัวเลือก plant หลายแบบ (first-order + delay, motor, inverted pendulum)
- [ ] ปรับความละเอียด grid (เช่น 40×32) และ cost function (ISE / IAE / ITAE)
