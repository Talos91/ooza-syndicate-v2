#!/bin/bash
# all shots for terrain-backdrop-shots-2026-11-10 (branch terrain-backdrop-shots); uses ../shoot.sh in the tools folder
T=C:/Users/itisf/ooze-wt/terrain-shots-tools; G="H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/generated/terrain-backdrop-shots-2026-11-10"; D="H:/My Drive/PROJECTS/Ooze Syndicate/References/Art direction 2026-11 - syndicate uniforms/DIRECTOR-PACKAGE/deliveries"
S=$T/shoot.sh; F=$T/floors
R15="$D/round-4m-world-mood"; FB="$D/round-5-lab-floor-sides/faction-gameplay-backdrops-v1"
mkdir -p "$G/1-terrain" "$G/2-backdrops" "$G/3-mixed" "$G/1-terrain-phone"
# 1 terrain, current backdrop LAB-SIDE B
$S "$G/1-terrain/T01-r16-lab-tile-current.png"
$S "$G/1-terrain/T02-r14-v2-lab.png" --floor=lab --floor-r14 --backdrop=lab
$S "$G/1-terrain/T03-r14-v2-factory.png" --floor=factory --floor-r14 --backdrop=lab
n=4
for s in r7v2-lab r7v2-sewer r7v2-factory r8-lab r8-sewer r8-factory r8-forest r8-cyber_city r8-cartoon_factory r9-lab r9-sewer r9-factory r9-forest r9-cyber_city; do
  $S "$G/1-terrain/T$(printf %02d $n)-$s.png" --floor-tex=$F/$s.png
  $S "$G/1-terrain-phone/T$(printf %02d $n)-$s-phone.png" --floor-tex=$F/$s.png --mobile
  n=$((n+1))
done
$S "$G/1-terrain-phone/T01-r16-lab-tile-current-phone.png" --mobile
# 2 backdrops, current floor R16 lab tile
$S "$G/2-backdrops/B01-labside-b-current.png"
$S "$G/2-backdrops/B02-labside-a.png" --lab-side=a
n=3
for b in factory lab sewer street layers; do $S "$G/2-backdrops/B$(printf %02d $n)-r15-$b.png" --backdrop="$R15/R4M-$b.png"; n=$((n+1)); done
for b in EMBER NULL SOLAR VEX VIRIDIAN; do lb=$(echo $b | tr A-Z a-z); $S "$G/2-backdrops/B$(printf %02d $n)-faction-$lb.png" --backdrop="$FB/OOZE-$b-IPHONE18PRO-2622x1206.png"; n=$((n+1)); done
# 3 mixed pairs (M) + contrasts (C)
m() { $S "$G/3-mixed/$1.png" --floor-tex=$F/$2.png "$3"; }
m M01-r9-lab+r15-lab r9-lab --backdrop="$R15/R4M-lab.png"
m M02-r9-factory+r15-factory r9-factory --backdrop="$R15/R4M-factory.png"
m M03-r9-sewer+r15-sewer r9-sewer --backdrop="$R15/R4M-sewer.png"
m M04-r9-cyber_city+r15-street r9-cyber_city --backdrop="$R15/R4M-street.png"
m M05-r8-cyber_city+r15-street r8-cyber_city --backdrop="$R15/R4M-street.png"
m M06-r7v2-factory+r15-factory r7v2-factory --backdrop="$R15/R4M-factory.png"
m M07-r7v2-sewer+r15-sewer r7v2-sewer --backdrop="$R15/R4M-sewer.png"
m M08-r8-lab+labside-a r8-lab --lab-side=a
m M09-r9-factory+labside-b r9-factory --backdrop=lab
m M10-r9-lab+r15-layers r9-lab --backdrop="$R15/R4M-layers.png"
m M11-r9-cyber_city+faction-vex r9-cyber_city --backdrop="$FB/OOZE-VEX-IPHONE18PRO-2622x1206.png"
m M12-r8-sewer+faction-viridian r8-sewer --backdrop="$FB/OOZE-VIRIDIAN-IPHONE18PRO-2622x1206.png"
m C01-CONTRAST-r8-forest+r15-factory r8-forest --backdrop="$R15/R4M-factory.png"
m C02-CONTRAST-r8-cartoon_factory+r15-sewer r8-cartoon_factory --backdrop="$R15/R4M-sewer.png"
echo ALLDONE
