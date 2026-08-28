* bpf.inc -- RF input bandpass filter, J1 (node "ant") to U18 (node "bpo").
* 5th-order LC ladder: shunt L1||C1, series C2-L2, shunt L3||C3,
* series C4-L4, shunt L5||C5.
*
* Inductors carry a series loss resistance set by QL (unloaded Q at fq).
* 0402 RF chip inductors are typically Q = 25..60 around 100 MHz; set
* QL=1e9 to get the ideal-component answer.
.param QL = 40
.param fq = 103meg
.param k_esr = {2*3.14159265*fq/QL}

C1  ant 0   {C1}
L1  ant l1a {L1}
RL1 l1a 0   {k_esr*L1}
C2  ant c2a {C2}
L2  c2a l2a {L2}
RL2 l2a n3  {k_esr*L2}
C3  n3 0    {C3}
L3  n3 l3a  {L3}
RL3 l3a 0   {k_esr*L3}
C4  n3 c4a  {C4}
L4  c4a l4a {L4}
RL4 l4a bpo {k_esr*L4}
C5  bpo 0   {C5}
L5  bpo l5a {L5}
RL5 l5a 0   {k_esr*L5}
