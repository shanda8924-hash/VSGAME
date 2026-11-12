# Minotaur cleave animation assets

**2026-09-07: このAI生成版は第二形態の候補として保管。削除しない。現時点でゲームには未接続。**
第一形態は`source_edit/README.md`の元Aseprite部品加工版を使用する。
第二形態の変身条件/専用攻撃は未確定・未実装。以下は生成画像の制作記録。

Built-in imagegen was used on 2026-09-06. Original boss PNGs were references, not overwritten.

## Runtime assets

- minotaur_cleave_side_8f.png: side-facing sweep; left uses horizontal mirroring.
- minotaur_cleave_back_8f.png: away-facing sweep for upper targets.
- minotaur_cleave_front_8f.png: toward-camera sweep for lower targets.

Each PNG is 800 x 100 RGBA, eight 100 x 100 cells. Feet/pivot alignment matches the existing 100px canvas (body feet y58; original with-shadow idle bounds extend to y60). The raw generated art is in source/. The game reads only the three final strips.

Imagegen returned pale checker pixels instead of usable alpha. With the user's prior permission for sprite preparation, tools/build_minotaur_cleave_assets.py cuts the cells, removes that pale background/disconnected scraps, nearest-neighbor rescales and aligns the feet. It does not draw/synthesize any poses. The front sheet's active start uses its left-ready pose because generated cell3 points the wrong way; cells4/5 then carry the weapon down/across to the right. There are at least six distinct frames per clip, not a moving single picture.

Connection: boss_attack_performance.gd duplicates the current Minotaur SpriteFrames, adds cleave_side/back/front locally, and poses frames3..5 from minotaur_patterns.gd's shared 0.18 second sweep progress. Original idle/walk/hurt/death and normal-game SpriteFrames cache are retained. boss_cleave_slash.gd is a ground-propagating cut at the same y=.065 as the ground warning; the solid weapon itself is drawn in these new sprites.

## Generation prompts (verbatim)

The back sheet's contact-center cell4 is replaced by the separately generated foreshortened pose below. It points away and is occluded by the torso, instead of prematurely pointing left before the shared sweep reaches that side.

### 背面・中央接触コマ

```text
Use case: identity-preserve. Single production pixel sprite pose, genuinely transparent background. Input1 is reference for the exact back-facing Minotaur design, not a request to reproduce a whole sheet; input2 the original character. Draw just ONE complete Minotaur in the same coarse pixel art.
This is the MIDDLE frame of a horizontal sweeping cleave toward screen TOP: the bull is seen strictly from BEHIND, face is not visible, brown broad back, short upward pale horns, dark wine loincloth/belt, dark grey feet, grey shoulder plate on viewer RIGHT as in supplied back-view sprites. Body remains exactly same proportions/design as reference.
The weapon is currently pointing STRAIGHT AWAY from camera, toward screen TOP, on FAR side of the bull. Both arms are reaching forward around the waist, partially hidden behind torso. The huge dark single-edged cleaver is FORESHORTENED: do NOT show it stretched horizontally left or right. Most of the blade is naturally OCCLUDED by the bull's torso, with just a SHORT compact dark steel tip visible directly above/behind the center of the head. No tall vertical sword/spike, no raised overhead arms, no stab pose; this is the transient center angle of the waist-height rotational sweep. Feet planted. No ground shadow, no effects, no checkerboard pixels, no text. Strong exact original identity and original simple palette; crisp nearest-neighbor pixel clusters with no antialiasing.
```

### 側面・初稿

```text
Use case: identity-preserve.
Asset type: production pixel-art sprite animation sheet for this existing Minotaur boss, NOT concept art.
Input image 1 is the actual original boss idle sprite sheet (identity/palette/proportions reference); input image 2 is its original overhead attack sheet (weapon shape reference); input image 3 is the current in-game boss appearance for enlarged detail, ignore all scenery/UI/attack markers.
Create ONE transparent PNG containing exactly EIGHT new full-body frames, in a regular grid of 4 columns by 2 rows, read left-to-right top row then bottom row. Equal-sized cells, no borders, no labels, no ground, genuine transparent alpha background. Each body same size, planted feet at the same baseline and hip pivot centered in each cell. Generous empty space around weapon, no overlapping cells.
Faithfully reproduce THIS small stock pixel sprite: squat muscular brown bull humanoid, short broad muzzle, small upward ivory horns, reddish-brown fur, pale grey shoulder/bracer metal, dark wine-red loincloth, dark grey hooves, enormous long dark steel two-handed single-edged cleaver/axe-sword with silver cutting edge. The reference uses very coarse sharp pixels and simple low-color shading. Keep exactly this identity, costume, weapon silhouette, pixel density and proportions; do NOT turn into a different horned monster or add ornamentation.
The new animation is a powerful HORIZONTAL SWEEP toward screen RIGHT through a broad front arc, NOT a straight thrust and NOT an overhead chop. The whole torso, shoulders, both arms, and cleaver visibly rotate through the stroke while the feet pivot. 8 distinct poses:
1 ready, 2 torso coils away from target and weapon pulled back high behind shoulder, 3 maximum coiled windup with blade clearly behind body, 4 starts unwinding and bringing blade around far side, 5 blade sweeps across front of torso at waist height, 6 blade continues down/near side of arc with torso visibly turned, 7 low cross-body follow-through past target, 8 returns toward ready.
Frames 4,5,6 must clearly be different rotational angles, not the same horizontal sword extending further. Solid tangible weapon only: no luminous slash, no white crescent, no speed streak, no particles, no shadow disc baked into frames. The game renders those separately. Crisp nearest-neighbor-style pixel clusters, NO antialiasing, no painterly rendering. The character must remain recognizable as precisely the reference Minotaur in every frame.
```

### 側面・採用稿

```text
Use case: identity-preserve. Edit target image1 is the new Minotaur animation sheet; image2 is the original Minotaur for exact identity reference.
Keep the Minotaur design, dark grey shoulder plate, brown bull face, upturned short pale horns, burgundy belt/loincloth and massive single edged dark cleaver faithful. Keep 8 equal cells, 4 columns x 2 rows. Correct ONLY the animation action and remove all background to genuine transparent alpha: the current sheet still thrusts the sword forward, which is wrong.
Produce a ROTATIONAL WAIST-HEIGHT CLEAVE with dramatically different weapon pointing directions in the active frames. No luminous effects.
Numbered here only for instructions; do NOT draw numbers:
1 ready with blade low right.
2 twist torso backwards, blade pointing upper LEFT behind shoulder.
3 deepest windup, both hands pulled back LEFT, blade upper LEFT.
4 far-side first contact: torso rotates back toward target, weapon extends sharply upper RIGHT (about 55 degrees above horizontal), hands in front of chest, blade visibly on far side.
5 middle contact: blade exactly RIGHT, hands cross in front of torso, body facing right.
6 near-side last contact: blade extends sharply lower RIGHT (about 55 degrees below horizontal), both arms crossing and shoulders rotated toward viewer, front leg pivots.
7 follow-through blade down LEFT crossing below torso, weight shifted.
8 recover toward ready.
This is seen with an elevated three-quarter 2.5D game camera; the weapon sweep forms an ellipse in the projected ground plane, not an overhead vertical chop. Keep feet/hip at consistent baseline, consistent size in all8cells; enough padding for upper/lower blade endpoints. Coarse crisp retro pixel art, same pixel density/color family as original. No new armor or anatomy, no yellow accents, no speed streaks, no background, NO CHECKERBOARD painted in pixels, actual alpha transparency.
```

### 背面・採用稿

```text
Use case: identity-preserve. Create a directional companion animation sprite sheet of EXACTLY the same Minotaur in input1 (new design reference) and input2(original palette/costume reference). Production game sprites, not concept art. Single sheet, exactly 8 frames in 4columns x2rows, genuinely transparent alpha (no drawn checkerboard), empty padding, no labels.
This sheet faces AWAY from the camera, toward screen TOP (back/three-quarter back view), so its back, back of horns, brown fur and dark red belt/loincloth are seen. Do not simply repeat a right-facing face. Keep the original broad short bull body, short ivory upturned horns, grey left shoulder armor/bracers, grey hooves and massive dark single-edged steel cleaver with pale cutting edge. No redesign or added details. Same crisp coarse pixel density, body proportions and small color palette as reference.
Animation: horizontal sweeping attack IN FRONT OF THE BOSS toward the TOP of the screen, on the FAR SIDE of its body. Plant feet and twist shoulders/waist visibly. 1 backs-facing ready,2 pull blade behind right shoulder,3 coiled windup weapon down/right behind body,4 rotating cut begins toward upper RIGHT,5 blade crosses across TOP in front of hidden face,6 finishes toward upper LEFT with torso turned left,7 cross-body follow through toward left,8 back-view ready recovery. The far-side weapon is partially occluded by body where appropriate.8distinct poses, consistent feet baseline and hip anchor in every equal-sized cell. Do not turn this into stabbing. No white crescent or speed streaks or shadows; ONLY opaque character and solid weapon. Crisp real pixel clusters, no antialiasing.
```

### 正面・採用稿

```text
Use case: identity-preserve. Create a directional companion sheet of the exact original Minotaur boss. Image1=new faithful side-view animation, image2=new matching back-view animation, image3=original identity reference. Only animation direction changes.
Exactly EIGHT full-body frames in a 4column x2row regular equal-cell grid, read rowwise; genuine alpha transparent background, no checker pixels, no shadows, no text, generous margins. This version faces TOWARD THE CAMERA, attacking DOWN toward screen BOTTOM. Face and broad muzzle, both short upward ivory horns and front of chest visible, no right-profile repeated. Same squat brown bull, grey left shoulder armor and bracers, burgundy belt/loincloth, grey hooves, enormous dark grey single-edged cleaver with silver edge. Coarse sharp pixels matching original style, not a detailed redesigned creature.
Horizontal sweep in front of its knees/waist toward bottom of screen: 1 ready front-facing blade lower left;2 twist torso and pull weapon behind LEFT shoulder;3 fully coiled arms to LEFT side;4 starts across near side toward lower LEFT;5 weapon foreshortened toward BOTTOM center with torso front-facing;6 continues clearly toward lower RIGHT;7 torso follows to RIGHT with blade cross-body right;8 return front ready. Blade must sweep LEFT→BOTTOM→RIGHT, not stab straight at viewer. Show pivoting feet, shoulders/arms/torso twisting. Same size and planted feet baseline in all cells. The near-side blade may overlap legs but do not crop it. Opaque solid blade only, no slash arcs or speed streaks. No extra anatomy/armor or brighter new palette.
```
