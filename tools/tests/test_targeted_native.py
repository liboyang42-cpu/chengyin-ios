"""Small, synthetic diagnostic controls; no Apple execution or repository copies."""
import copy
import atexit
import ast
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('targeted_native_runner', TOOLS / 'run_targeted_native.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
DESCRIPTION_7B_TEST_SHA256 = '37b8a210e51c0c062964fedfd146313e53895fb255f4465db3eef0f0aaded993'
DESCRIPTION_7B_TEST_BLOB = '91937ee7b9690b80de047ac24bf0748bf95c50e7'
DESCRIPTION_7B_TEST_PACKED = (
    b'c-ri}Yj@j7k|_AyzXIdgvmmP}3IG9+lt+E8EUU`emL;zwcg-A?27^aJLYpKw1Zi3A@qgcl$V|KeJ|xR^@7bE^Dv<;tBQxWjkrA(7'
    b'zrLEflSxlW9%svYwv2owh}^qboZz2+JX<c}N%BUS#mdoqK4A*`%KX(bif2l^P!?<+C($xqJi?>%h$a2kuV254rt^5Q#BUzu-|muq'
    b'jh5-BB>j{BXA*gR06LN1{v(NJ^6xl#6)xhbGIy8v@SJ!<`3N87BlAg=APo6=!Q@{_bT@NTu*u4sFJhl1N&3xW`sb2O=V3HSUtP_j'
    b'<&puWG`jpGho8p&=U1<;FD}lmltV(M<2d-b<8=EAmc)}Utkdn!-36O1lN<f^RWfHjJX)M^AHQ{Q1pe|Q_FY`uj=FRgcWlW5X9iz<'
    b'Va{STo3Vx3Q}~$siVEL2rKkGyN45KkKUy7Y8V4&FgGR$~JNU0IA=aP7Zon3O++Bx1*WqBguZ}-mUY?v^J94u0-&Y?mF0YT?o}D;X'
    b'Cub+e*QXcf@DqOp=I;g$?qMfIwmhALO_+}}?c;N5Hp<n-r_19Lxu$W_XR|NS0-l4{JL>h(<!>j~C-0o|qwCYZpNOZO%ZrO^Sej(H'
    b';3JB4?{?*4^uM^1C;%#Sa7A2ilEa`=ok~wBqLV|fI@=WDe8B>S)D<sUp?6=sdKIux@eMb0kf@w!HeW51PWn<$@mC9)!NDs9{sFE!'
    b'`3h9-M@!`%Xgyv;zB^IE=<9N|U`hzAxSIL*?(B{Qqrn^bwr(m>qWJgB|I7k-dXX&quL$5ZKvBGSH4ET}FA;kHo<XoIQR3O;QHkJ('
    b'IfH-Amhj14foPb4K!61dfDs>&S`_aQaPJei)1@+FUx4Nw77=`@EbkZb>h4}~m3wy)OrqImm{B|h`GLQ>$}~!nXm%&@RA~M^1?eUs'
    b'fbJ}YAr}g6Y!4+3pB%oMo4=bRY(Ye%ywASP$*&|{Eqq20X%!M>l`y~#CNKCY!9gd0T)<$^0Dfai!hn2Wsyz^PuD?{iSV~5&azE(5'
    b'W#TFmcioQi7x`)j85N0F3p7O7CyhYj$(r}8Xz&+FtmDiMNzxMYCmo5?jk=6M=I;YweK2xZfCApZy@_T3*pY8@&b{RzQ9368F99wU'
    b'7`?stbpB2-&{bFYpZssfmnTQp7njb*qwDwO-!4x+9-YdcGT{By9M@Prb#)CA;Mm#h;ijMERBqIexyVY6=Pvzwx$=d{t$k-TM@ir$'
    b'_pV{t#aG=R=oD8~Y@`?owk`gLATSc)_$n%-c;SL>JxrBT|5|?eE?U3~pm{s6<sb+SQxUs|a%GQ;lsy59>t7JecfcoX(Me(V{Rwkt'
    b'tGOV{I9^K8n>{jfr;Ps|lFpwHsR7dhe=T6Z4oy;sD*Pt^N{VKr$dEu0=zjWM-BUtd_ottOXweZ$^YD7HA|3>ko%l0-?51x=VF43K'
    b'ycrVZAxJbiB(yS8mmqF4z-*ESeR!ydja#F^HXL|8vx+A(md&G<u;MtJd|;8KB&}Izv05Ne#pC@bA#0=4EdnD7a3heAe|IM<cCuK+'
    b'i;nt1$m$xsLo{}vsLEf`QM(0*puSP~cf`2TE&@Fr`Afc`z5H59;Rw)YDBgNRJfJRfnmIKPD(bVMqpNCM+AsphzSvy#)u&IV@8Ek?'
    b'(~W^?*~2~jqx3KQel*r}Rp{?z2}t|Sa>2knV}86qAqx2R6psO?FtNPiCxCu)n{iS6fMlDZdZP+xU{br$!V&sTy*+qU+CvUo;V}4X'
    b'D|n75^+Sma#n63sj>^2F>Y8Sors7RvkM9~n-~b)`QpG{U07z_#>V_aL_;0uHg8IiYeGj=_in+XCfa$wHy`U_JF$?1Q-RaS9=NDJ_'
    b'=i8&J6X)&O#oMbs@W(XCQ{%#YfaU6xBuAGUmYhE_LZjIn<_0ZJK_GDNCg?u&K|JdnPfeEqZN>?kbzsPD7mQ7`1Ug;#!BhXxXs+->'
    b'|DJsfBG`{*ZrpW?OMhfbR$vf8;sS)EC-9gUkdr%0P?LbBnNGnb;Y=V_2PP-JzR?c`wCgwOf_>Qop_wqSfz|gXNAG}a<PfT>D!(YE'
    b'w#D23`3*_>dmf0l4G^jSaf6R9K72U6#$~8N%|Ca2d2+H9^!KM%U_hK6ADuay4pe@nc1+GlI3PNeYGoa91kO8^SvKPjhVvduTwLKj'
    b'mS0$P!<XiHNg!XwdFFAERuxW+C~wA9Y5tk!b^BxX$L!<EgK6J`Vd?{~fxK59q9s~=YQsVa@zXXT{$LP=VNN<pdmg!*BX)FlcJVuS'
    b'cE|6J&VM_(%7fr5QbShA;1v~?+2tRPNci(9|HoR$a``p`o?FNg>fOpl{V`Mf|A?bmM@+lhut<|+5BF3p2>s;>{3a<3ZmfgbZVk?4'
    b';TDCz5Q2yGlWk;%6!-XnbXHYq?4~lL!l+wPu0Ki&QBYu}3TrfAMgQFv?YIrsj>u%|CCszipL6Lr`)4b7+hR%zq??VJW^Tj<s3Cey'
    b'5IsWf(sVQ~9k`KsB)xZTXbSK$IP%p;(=O>u+44RPlAglt@6@KEF}|tz&^f4V6hSxN)EWGF{Wu2>Qq*e<*L|G0GZdic!{C?y?+UHW'
    b'@DacB@1sco3xuzx*cV}Znnf5H1VG+u7I0ZCKyiGUz*IpII>&C3hruV;UnKKMwCt$+@RQ!X+0$wBJ6*L`+;M_;ib0tujMxI9?u#`R'
    b'kWxThP$aiq2?iBfvYMbeQ$J$VBv8K-;qcdxdc->4e#ifl0V<?avPb+yG+$<W!I|z5$dX`*O+o9cWad`jXEZ0*&z}H5Tn~7&GK)+O'
    b'(yW*03x}`Mr3A%z^Nj=g-v0)WzAN7l)c0Fed7ZvXc=g%WC7NkBDWt!U_Cg1?4=a@Wn$M0DeMjqSnyw_k2(uvR_NBcm=&zGWb{d3J'
    b'`Ap3WNom@xfVja|_v6*9O2hHeo#32~@mJU*dI~m;FE9R*<h~7EFbdLdHTWj^9Dxm*`>H@TD*HMISCR$4!i(Ux$+rUbB?9O3XcipD'
    b'voN|_EyxEGoWy^HzvZ8&0enC=={qM7e*)MkSJF)-FvP)0M+VFLG%468F=Jc_a@bsdxpF5C1t4Vz1m1Mq$;7cO2b|)GE3iRFILx^Q'
    b'__5Cee<%M9Ksx0ZTo(1h1BiaW*c|`pWZ_roL*gG<Otx`=8*~ruZd5_RKmtVCcO{v7w}@ABl(9YK#x#ME;eW&17Ptr&!(P)?aGZ_s'
    b'#{vp~yKQw}6_*v<^E>dQCyp_8#G?*q0E{!huwPg}i;MwYN4Fg}2v|^F-U+*N{YO$>QdAzz=O_k=y7n>t1da^5x`+2J!5xE5r!yc}'
    b'aQ?)S_S^>>@{)xx@clVPhObtOFW~(o7Z0#mXAEfK=<U(T*Lk#fyjUE&GoMW+wBabMo;>o^%$+Cq@$%z>hjQVO;|T)?;*x!dKf~|n'
    b'X}u-Qd&DEnm+ZfB(5H?*iD$rv(u2EX7}QJ7;60l1B?A~fn}Vdd1~g`u@dU;XNdF~I9hwJ#Oiia%g_VYF7GKh$KN0?K`06_rx}ZkR'
    b'qls8Ze4H&{4!Nn(ejf$#d`Xjj;<#t>2^i!ZTY?C?TKO0=!<pj3@!{t4$>Wi~h?C?j3fVH6vSVTNJaKqD7o%z7dJ2k`<RyvP(gxS}'
    b'u$_DjNTL$8J#p;wcrkS+zq%CW{pj8S-Qx3n6_9RV;*Y;$bP>pR>PE8*aIu~?<i!er5fu~t90k*8d4h)^_(nooFnc_jOpbzoz)WY$'
    b'538k68c!S-DYT%5#I)bVEIE&tM-#y7EcV^Wy9F4@=?Y)Wh{pI{KM{v30Eof^SNdcER0Xh67+xVBC?Alke#QMqYy~ksbxiy<H-+S*'
    b'5Y?Y%i3<XorhGytFu3?g5VPgc3Pd|>`(u9aV~}OVk;P-PyZ6`EAG0A#Gz_vAB%mPO_n?m#K<@Dakrf~lPNKW}<;CJ+0!)Ahh3#X)'
    b'%7_UU2FXT0nqUm?QAqq$NATU0kN+M4=BwqqD4FBY%2S7gbvPD>HlJpnXYm6WD><Db4I{#$1m}r^7c`+1O{5@*5|E`p5&jD1A_KNU'
    b'VRuQEdh*n9VZzaDMbpCt;8q^30arJCuHc!yT`ey_kWAb;7b2h|my1U{(0(Ec=j`Ec?C}9SND|Swn-ljDDf~+muM&W~czmW+Mp-2f'
    b'$ob-eY?8ZriHtgvFOjYyUj7x&!;#r(!cW9N{BX1sEQE01qIv70>>xiQIRZSHpl$qJ*YxKZRVp5_k8|Mp(|1T(e@CPEWIA6y78&e`'
    b'!(M@lm2U0BZwzEN5t^`fKvoDHEsdM}c%M$|NBeaWKjfI!CwGTSMIar_7{IMW5d=`LqPrQaqL>xFzWor#_vo^*Gjt!X!8-(rz=c9p'
    b'&}{}#SVw>@a!>Hy1<fTDB<VJg-enVaQ^=S(A$8D|$WO?v#&pFc*(n&C9tqa%2RVzp1yL(Py}Ad{a4LM_lDHH)`D*2Xb+G+7Iqmt@'
    b'^*<9sf;m3>8+dBT6{XU=%Z>!Mhc9G2sLs#HTQKgAd@gCpI^;v;LTTI;1&8O`E`AtB@YD)EFbPzi@<^Yfrc&$@BO%}0eM0VnfrDp^'
    b'YrRK2HYLYVJlF@;Sb6vbpG$X*&nafSr{rM3Xu6#{XciFz49|D!?VAs5fnh};O+Q{-yLTTW|1(?UNOpzd7#9VE(pdzQlBMXt<G9g}'
    b'pJdL`#q0uhh0_?&!|9B?`P6OUP&XaEpFBk2QiUn)i24<qMt%%NF#JZ2MT!`w9%-YIVNCp%`~WOp#M7?9dF{B*iusc~^`D9T6FvQ('
    b'iTWmyf}e=rlOhd25%1@SRQyczpBm}-iMa0?Dfx*gKPl4kGx2_|NX<{2!_JYOpNaF6BSp`JeC9Bg%^TYB4CTz=<3<u^y|<4`ZaIAd'
    b'-(n)YcK9s@qc6jAlTn_8U25eWuK>*{p(r9C;HICUtRPGEIZ*<i05f`UrA2h&5+I;(%6q=(zJLb@QjA0vKJ9^{B;Fu537s2Szf4|>'
    b'7)BXYF(gvPGa;CZ-MN9_dXYCoDiDcsf&1#tN_OUt#OhZ%6-@&o81hMSF(2}0UmhtujRQta_fb44R!s&tFF-4;fU!$4f*+6HDM*6I'
    b'o#dVo>jdn{_wfVRFCZn!?g9$qviwv=XmMWA?CxcdMdA`a@}RXKx+6@Q!H|@Q8F7O<vl3qhyL0wH0+bf$<06XlEWjO@O9sBeEN`d&'
    b'NQAgY#qv_48Usy^2yYqh`tev@0X<QqFkwr%Ry-a&c@z<17Q8s0eww*lQ~r|$$L?f;;#LG9fantO9^XaMyR+qsVn+e3I%NPm`2i&e'
    b'Fd^|Lxfq{j6HpH*Q~=T7WpMoc9xr~)f#m?D^LQq-0QtLw)LVFE%049+{`mR~Jo)2Kxytx8kGL78KkRJm<q>`IiQ0>!{G@ZZm&f**'
    b'PVZhE@omriUL3(^Iw^c{yq|Es__J``=~VK?k=^Mm^J!TAz!T8S$6q(b?uc!0Zu$~vY;)TBGWhItM*9+|?S8WR64-5j9{dtmZE}jd'
    b'6Dr-((X-=4vj9W}UB2M=sXKJPk{>dww>@#ulhUNuWgq7+m!=2R*?sn1&Z`T^w45!MrqfgK0$oQQC3nlo%5%1G3h2o<odp-Yj;Iph'
    b'BoBDSGH?QUq)chd4~rOn<H`T!EM_{Z$C3_!KH$#b;C7`T@PmMhe-f}g4h%noSX;RG$BL6d{`MXIGX+62Thhg#`W*8&@;(iJGTWdV'
    b'?Y6ot<-6L1J6>p#s2>ox{yd&{iZ`t3mQ(t8Ha-3V3`Q65AE*LN^Luh7(zh~l!%NW{dTMkhzw-XSYyp7Zg4#OT+A_1k#<osx%Y*xt'
    b'F*)&wEfcqci*zE;=$7{~VH@s%kWO{DfSr|91<BodHY{7-l@OOxIB8~gRqC%f<3A5zRC0z-Rvu!|!O0%tzd*ENEu=nqqy5-J))nIb'
    b'`=kuv9ABJYUmhJ_J6G?Ius%i)5rvm?V&oF9g(aP=_(1od`EmzGKE29O5-tk{&_S(;t8amnG$=SSF(Twn?z)MCmut$>WCLa=?yl$d'
    b'6bvudLcioPh~SAg;x;V)j1T=qQ7<slA=}rQmk=HPR{c|%aLGv=b?s~Ld>^$?M^35=kN^IeJswWnsTa6Nu?J0B;<>4jDDim-?vmZH'
    b'uQ{s2D^}50*bP3LeNkgWUJz4DRWmjx(Jkl+?|bIURBWV03Q{AxX9wa4Kp{k4KLNkM?M?ZB>dU}G{O%h32R{{bsW2!c7J_e3gePUq'
    b'$aR3cv5N8#D=di7c?kq(8F$2*bOqtaqB)JUk|Mi?KAxN2(koTCbfPp)wv2DG-}#%_*!**@*iA^~tvd6b@(XAqFpqxu<?{pn1yYXR'
    b'1k5%B7IBVCM`S=sv4BS%kitk}8uJwNPK(-xMmoYe&cp?y`=?^bR9@z*U2Sma@F@S|*>y|}%cHTonnnM;Vv|ROYlQ4(>-M}}R7aW0'
    b'$?KXZabQ%(b@;eKM^!F7$`U^ym1bC~jP6~Ye08y$+JW-#$MTY;^6igVxSIJ2k8@!alW*T^zxuAOy-q1tK;9!1C4B1g#?|gkO#nt9'
    b'D1vSb-58_1EVFp##W5D3a=x$yo(qwJrmAacnXx+C9+Xc{`GVU=7Jf$+uVZ;cUR0=~Vm%lKFO_poR+R6^exgDPy|lDRw^w_+Ui{PH'
    b'H?|SZWU{y9(<V?0aGxm(kI`5DT~-wnzo(?def&=CZtq11kqZ+>*+^4fW0|31hX1WKtzI?Mwb+`trHLi90?HWLM(MuYt=vT*oVx0T'
    b'Q*zZr*oM1newrebbKJO1z3uu{{3<yRn(1Pkg9f$6wP~i8R1FEmHfs$3Jk-o%s|Q=_!=c^Z@VM|FzHx<mps4-+{(KRAkv=R(@E}F+'
    b'`&!FgV0$S4csWX881u~uL++MwZ$6p?KGF$?6)%!4D2Cux-22R%m%yp$1B%a-FZYDGgbIK?>`D7|Yc_4P|MlBe8swNCRBZ69ib6A`'
    b'<(>U{2chz<z7A&UD2rFcXQKa7{7hW~DqZv@?CP`Oe%b$J9b~?R+ksu1>9%gr0=XQt`dWF%9Tj5rc!02|4<w){sGHbd4l7<^i}Uv9'
    b'l>t;!1cVzFx&Z@->-q$wzym+Ha>CVQ;v_4qnHY*xjIsof+*T9+<nA;tM3EWeG^qHtLyrQ(?=PqGeO?!(|8+Xa6&nFj3+Ry}!TMOY'
    b'Hp&$d694UEiQKOpb#ISPM#b76dd~ALmOm-)Q>lz2Qi2l&SqYQ{KRn|#VbneqhAF<1ZPzKr?9XE`?*!s~T*E0E%N+^16ly}`NTqTC'
    b'dLqM}`)S~_(=8)eGivLQupR`h{ytLU>s4E_zb4m%ACU!bMFBuOY{vSbl-!}V-G*x1(%EXd_Yf~WgH<W^6;?!7OU_O^$JEl^x0C`7'
    b'K)`>mrNWZV#5^14E4pVghy@mw6D<=bewYdV;Urk6C^@UtpA}$<pyC!+7>AE57`KLfU<>=aQWLxYWP|l#ioc1%Lyg2MYOExLZGxCe'
    b'BtQZueSWfy%MJU2l}pI@1`;>`Yq|%dTlx|<Ynr>NSK_+cHE2jepp#b^FjtxsO?!Q_*DLgdM}d<Gn@BYG*o@9BGuk@8P<Mnqb-zYa'
    b'AXjjgL=9LPWiR39jqxHsi3VzJ9dM5xCzwJ+?|CcG?P%mSf&hVZIs@!r+VR83Mf@c~_Y7Y7L`9U*0L$uq73dw=E`*oB{G)spEK?Kl'
    b'g1ewr0yGiPUd$CJFO$89o#hL`W1-jn9bmum_T>P{KCi;NCky-bAA$YeG{wvEr*>2rSSi+iBBGN;Pw^FA#fr*8@lXmz81Q3%g7t5~'
    b'2`CWvzqU#$&_m$;2e6!-h5DaD|0Y2D2TG^^OZWeR_2hVAbfy2Hi<~ia{W#e(?AAlOGT_c14}a+%WbkAyu7AW{a=^=zAw8sn$i-_I'
    b'1c`vV$SeVgH;wLi>_e`76eqXoSX<3sQTAZ!f9Y0HowEfwVL<KzV=cp&&Lj&}!5i@gDKBX;5ZQJI?YQ!{FmQqT=YRrT>))7T>;kyU'
    b'$7;|s%*TdT!Sta-;Wh96c6#kxpIm-8JwG~gK3-mY_;`J&DM0DUp08v8`(SUvFo#OWU=|7}xERR(E`h&*jh6R^x^ll<&Xa@vea<Cl'
    b'_3Td~FMb5oY8rd~e6<gIIJ<j{X1Hm{OzW$Pu0<b{@KB&kquFYS6k=NI=Zuk<1Es{gds)^08VJan@INmKU_rRaGh-|u`T#xwcKk|z'
    b'f=3m*!5(mB6aox#DM8CtzDyXbEf^-evL0o81bYIbJ0ahwKZmHM$eRyfX?OHMBZr=WkBWPDw_y0GViA^QX^MX9`Uts8dM{lg*ss0Z'
    b'qBPVDBb;O*dM5#tr|=nNEqoWOd|9iWmlR9eP1G43HN~x4P7E4DkUYeko`K|xPWOt(2EA%U>g>cVgV3x4kfc%kcWXs{nE;7&M5W9<'
    b'zPGTxFxt9TZVK=8#0FsrbgZz)^=eO9CGsypXRvqk`5so)<Do}*B;tSFt{XSUD}T(^Jbd;3=<*$~?x*u>ShnF99`BS2rSIp6x42l{'
    b'v?L%;Gh*anQ`$HdG+$p6Q1%DOSH<V_x0=z(5uWCXm@qhuc)cz1OZDx_#8_>!k@~9(fu$(8o^&cD=3CSeb*m7t$#t%8UeR3}W-p&m'
    b'rF{vi&_M6r7LI3H0@kW$1z~7;hBo$@Ikr5{w6&oX_`ao^uAwn6FqmoCx;qYZ<_=sp@H7MdKO6;v@xULeWhQFHOuN0s0|Q?0GW8`y'
    b'M}j;9*1ufOboZ;-=c12a-ZBwx!3Rr6?NwuzBa^z-_|6S4w~Nw4{Wq*nfAUu}@?pNE$9Rd};&YqYD*uaes}vEjRlc|jZeksF{s{i^'
    b'M<4!$<ymE0mmZ#F&^;6&bbcFB>s$O(;R_ba^-Ev=GmfYDh2Gb|A8Jww{J2XD0<uzIb@QKp%x-__sq4wKEQ+`3Wzt5bzQ%0V8d$m)'
    b'Xol$pz6S)T>y`lo%SOIuj|M=pVW?YdFw|^g=;|gjjIj&PjE2Tgt>%4zCd2E};Be&-aa`XAJ15Cd70p_*<EChaXGp9pK@c*ke>%bD'
    b'b!tn&u<iPKA%Gq^7e(KR_uSgFXV)90sc9GgPq)+sg3f^XPc{5W^UJptt84osjF+?vid@O`fqeWdU3dw77s{y{EqkIEuDj19d`Y-a'
    b'BHjjaWZgM-HZm6Gow&0ZKbhi->(I&EVX<phbvZKiQ`>K-Q&v2g{LR5gEw&;I-WG$CX|~=(X@$NSRrR)of<p75po0o6M2fAC3KpSD'
    b'7U2!`bZNtmH{O`l#U3|_xox*hfK~l!WcgUdBOj?o(z9uq#!~n8x&~1<h=j<`tSn(QfL|raRG_O8p9(#4Otz2iKaFI!UcNUVXD5y8'
    b'mL9Iqf^D)gX>Lf`iEx{hDI|vcjXm;3+TaXi6PvP<r-<Etgz`x<pW`re(Dsm(`!NbUqZ1N%1X&Wsn4_~hb??|_9#~cAl~P-H%bi+p'
    b'tG@3}{w$Vy_$fCCL@+RMS87NRw9HUTO|LZZs0VLRu%<N)gTr47tVVbMqIDDrpn&-Jj{=UfHWy81jx}Y=)}OiIS{@dC*e#hdM{*g#'
    b'6n3@4XVMdU(p{erpPu&!=~O0*CRT3Av8d**r;J@C!nG;wGMTy!Ms1FD%L`4Z*X^&=&_``f$QEZqbw%qr4mp95y47?awbhXZNA%OY'
    b'wqkzUk*QvCoMihFd02(HEWKQ-pHd46Y6O^$kw0xI3A?X|IvI=!Rr-gwmyhu8)k4_qZo(?{{spwg)85>8={sMiSkO`ZHwuy9NpkYn'
    b'?C-x~*isddd;Sa#%=7BdJU@I*r%3r;8X7g^=vThyjXGW{4X+uZkH>3eA4W|VOCU_mBK~bZLoD}q^4IK`Uu=i$Hj8br_)>OYo>}JR'
    b'n+j3It0msKPw2WqPf5FXXln{YQooj-Vw$yQ_gOy>w8p=na*{2f9gjW6*wFz`fag<z<+E*QNBxPrxZxh=TYuDVV7fiDnjmNbymXFx'
    b'*=uUJ(%o(I<a7V3T;Ya%{GcXE!Y{LiD>Szva4kebY~?Gpx|ziB=R~BsQ>RCm@4p{kUww||IdFJ7i@&%^5G7OzBF&ap9`0k@h5~F('
    b'AS_Y-$riCfY~C+r!;`=v6TnkX_~U`1DI(lSB2`mDaZkHX_C;fN8rct}A@<Px9`CGzk(GvLZVvYJ+pVA?G0AuF)y6GOO(ieimBy17'
    b'(E8g=CJ(NfPeFhwndq7v>?Z)1xYCZm{&jB)Hb?eyc7Gr_Sd*QUy>yuUd2=w<Zl9i}RKs-H7;D*#&b0S{-n}^Ai?ER5Q7_f%GCf*`'
    b'KnmuE0M9T=ofej?<lsm$%ubZ%a6J#&7)z!&*n_Cf!{8iF=H$N#U?3ndM9Oe0#NUDw;Zw=3tf=U}*2?fI?TWl|DXm3%`D@Y#9H&$w'
    b'Be1^~gmYcPvvqp)$+lfd4R4q%uN94VTrXT~PyIKsPqf0`+7<jAFF-b}+J13)Hi5VCj>slquLTX12fIDkb!AIiRVHwB9l+0*sYfEd'
    b'o69wpNt@Ms!?h$K;B;h1x>{SeS1^HP+HAMs>z05!(MW2B=ZuJUs%k(=YX%@&lF9$-24*-JJcp|yG~{B+r2hQvYsYf~CraDW6@>|&'
    b'BfINUxcPI%v~A&iWUfbvWMCRD?A9*(Qta|bt^EKJ0=&t!6y)Y;+TTwkmm)(PikC{iw&r?^DIQ3?zww-6@kL?W@0+G+ODyPi$}U;j'
    b'sfUNtx+ympB#7d!F*g<Vk5LqGK~>F0=592_@(7$r{=0qlbmRsW#f5Cz@ghMB%3Uqef(6cWMOTuR4jQxzpl3nke2psyL%S1SN<$ma'
    b'TN8oRZP%yEGrnU8@nC-+<O7CACXA<X?n~0xr@q&92n!df(_Mc-Z1a_`6=!YuH~yAoMc3u{*K~^5En|0QqC)q^iKiH!!DB@*EOVD#'
    b'xO3qMZRm*9ClZ!Em0)SPdrscb&24Ta$rH(amOILSEB}-a<<#GgAZ8}EPIJMl@t)hFaWDF0lKj3BE*HGVE3x8VC$f!%D6oa!32B0V'
    b'riJb*v1qP_i}AdSh~DICB&6Mc1vc`=Tv~XcNOmGNo^0Ta>}=qzSH)yM%V?~Qog7i~nmuI?)bHN-_8C!1SFI5*M5Ii}_mpXd(NDJI'
    b'_3?;Kx$7Vd226@{?-q<|tk%-*bLi*il9btRJhHj2Gq1{*px8QBQ1<uRA1qb!bmA_Ti^!ws2{9V2<>71XwJNf*;e-A<4UOQ3;x9tr'
    b'&=2)zJ~^A8ayoNEf--ob8&I<PYr<nsu>N5JJ4yIm_~cj2$SpI9<ORAgkjTEaJe`kNW)?g0iZg#^qwCD2j=(59Fxw~J4;UndPG9ER'
    b'0n-5*d{<})EWfO@0hT{hMoaHdH?{}{H}<yiHgnFS_>mWw8$B9%0WEW8o^&+R<R_^Y*Y8g*)!YdUtR84}QI;`c8#F>jUuwdfXa?E~'
    b'HK7yD@8elYI__#2Pbq_#Tm?Z`4RTgCYEGzWb7uS@i(bjwAbt2t;MtEZuJ#OjPZO=vh2V=mA_j^+q=e`ol5L;iQ<NNi0pg+Rq6b7J'
    b'-)~#bYn4sVSbk~4gKY54Q2G9St<~z^$1zBc^l}V|;qDCwep@D&(&_fM@4ez8e=mRWlvSsz0vpY8cl)3+eR)n?%1T(F?&pOJo%=XJ'
    b'b9U<bB9elo3><!`gXhnEskwy1W?v%Mxhc;u`-T@4-hX=Q98t{j3TM28+2D*XKb@bSTskM`e?PsvIR9{RevQBKMD0C3I6fu-T%LTq'
    b'xH`SQxcm=%s^x}4;hkUc;ROqm{d+up+^@Tbl6&Fg?|_AKe)Qo4-<z+J`#iKy=g#Rn{6RMcrSFffuTMUFqzUNi_jM^{$z#HE$(BH9'
    b'l*S2S;{mHk)K(o?Z~}62OWVo)T}{lWsFj+frppYIP%bn{{oJzkip!RkxTr1^&IE7nE<}5-0wlg<n7CT`UM?B@sMaNJq*^72{NjAq'
    b'>y|CKqi%uAi4+@e<s_P|zN#B5v9+69DxSzs)_^0yAdeD$evZs2-O3r>8>QfV^++A<ub$KzvM3TibL-r|OvDG2IxvwvpZ0bU0Y<Nr'
    b'DX6K}T@;l(KcS~s!d_^Wy`5~pzPS2^RG?wFnE>XGLin@J=9uw>Sp_HlhW_18Cg3x6Y^{K1UmL7Nl#dOb*iIHhiYV3++Qa*>x#6|i'
    b'vvfM)!TpP8SpSlz0CFjt9jfED3iIAcmhrs0pJaVp!B5l*12s?Q<SQmTV<@eZiwcjXU&xYXB%wtPZgP(yN?9%k#RLDI%H<rS<#N8S'
    b'lk^*l$?T`!FE0P~>)FNcSiUKT!}of>8F15Sv+C60l1=BBcuiNwV=R9A4wM=7sp@nUH=zgU`>MqGN9<+P_b$Cw*2!Ne?NK4HP6`FH'
    b'YU?wicoDIHEvh9wBt6J8Jzmi(VSYTrBS_z!V;1BgcRcFT!3eSpb#zpDVptEU+pSM2<LTj?_&rr^z;S{ZO7ix1X#noiZieHMSN1AE'
    b'Xu=Gctwh)jsdjBSpjFYTwpSDb(Fv}tlVI=3a^k4unIZ&IPBF+QK1MIk6}4jlk@a{oynl~cwKU4N?=5c$dVzNmj8d~Ogx?P3ed@ON'
    b'Xb&sz(YFno*C782dx9q&zR1_pc%8U{e1y?aztwDAMFJD8&_Q-a%r`18l!CRo#8>JbKO7g8xZv@jp-C5ggJEtW;9LxLqeQ{KQKHb;'
    b'R8t@whG_M+W`6RS+YJVz=`){U5<_-auljVSNC0y9?&By~Os)($k4F7&HLRz8%P(zjkw;JxZ+LS9-zz6BY&N(70QHgf^tBT46^f*Y'
    b'm}-qy72?kMj0MC&WdarpXM!aJP?b)w7cpww$zzrXQZ6AN5|<7+FMWW2VZ}`GbwArIctR_`g?Fc?;Q3Qw#XMJItW8)vqHJF-_XNld'
    b'3!-dT=@f${VmKhvkD?lRL4=5(N!!iwfz58+W>!qfbwXkn(^85SpbD!DW~bVozOCeqzM3WIuDO#!)9Cw{JBsR~&r4t4$iXp~oGwfM'
    b'<LSqf){;3`eWn>8&`hC@?M8e16)hIIl4qwMPOq`tM)yZ;?N-@PmHiFf&#Y-1tJNn97sQ<OVixzGE4P6gGMir0M=5(Y73|&DJ%PtM'
    b'xH%goky1mX+!e~#lz!}zcoKi-2CJ*Y<6|s$HFq9d?s<6_?PEL&;_w9V&(UPEr9_!i?I*ommgKZH8k0F%zvf;a@8=wJ_|{^0_ZBVa'
    b'A3%4FKw^9u7hry;lIX#|H;Pw@_*kP;RVLSU#dvP~l%0iBEV?83sO;<3H<bepRtZ5%02~aoD|Gmub-R8%8colQf|IWSn?!drchbK)'
    b'{q6Mp8m%$;5leaGKmYCY?CiG2_os3UB84HnIv_8Y3Eh^sA+Owop&e(5O%W@e<CA=)MI0|hMdX~N@J7M$=vG@yb$8w|Z*`aE9-tqf'
    b'zR6N<=wW#3<79PrI!pHJ4yQ$hsr0q}^m7nlO=<MRlEb1?pT7_)Fn}R*MXCx<O4<F54gq<JOTr_w_{Ccq@1v-^={VOXSJ&?^uC5(t'
    b'e-ng7e~|Yvc8|)#xV*SP7&S}ty_EYyWr!ZIl9{}@h(v^!k%HB9o^)se-OcWDa!PU1rRd-S_39G>&_fa>kdk=vrIH9q$-T5({8+M_'
    b'c+r#93U|E7*^V+Fxm(@Jo5DWwW8uOUP=3rlTl(soo!0j0xHl|!1Cs}m6&-gHxry)-C_6Vsu{Gg*j^JN{w*^{Bp1a5<SF_&)dluKN'
    b'lfJoM$<mSR(ye_HrpE6-r?0P~CU%A|+BWnXKNfH2Z^4@lI0Ao`D1!DSzaID*mV^G=Pada}X!aRP-peUS@<r<*-QF50wlN#iNOj3i'
    b'<nlFfFiXHsVnJzb5m^@G*7uEkFh3Re;rZC25&aTNxKl5>Tg9tHGDjlHH(;KXSkk&Qlpn$f9l70G(Q>A4+6WOFCaeQr))Od?@hp)`'
    b'WAHY}aeIhC{-(H6@d>&Dm2Gdg`x7N#HA{~~g`7K}pU1Snnj!t6*(_wea1yc_*;St2$8gO9C?dvF+)_Sn7_(T=^3Sn2MK-{zzcbPZ'
    b'0eE1@1yWbY>{-qh$hDZ(iffj<EKhjR48AF?o<~$!%Dko%k6gyRWNdM-8Ubzq80oyN6eSm*e6U{YSPfJmL?8^D6N21~*gcP_Zv1k3'
    b'5k{c1qj*s)`QCM?g8?OpL^GfQCJVvxB*^NKA9z3W73Jm-M2fkfuh8fkRs!1T!A|LLrah8Qh0a(xRL!yJZWfTr2je@^`O6MlZVCrf'
    b'x4DK6#p-_%lh>8*c~wU00zrrFQ5f?7E_fAramQhgU;fV8!--^5tQ|iI_IO=Vo(z?%#a_Onz(m453uHyr9x+f&yj@l-!8TB|LZvtA'
    b'0>XS=n8{DmqN|y*a;ttYpawj2pM8(=<`CESCr9s4Er@d;)#vNg4xJWj1L&>wAW`@H=QrG_?^`24yHrHrHv1t3maZW+Gy3qy60B@&'
    b'?I!xp*VSCF3{~3y^@C=WVCC?I;;;PHX#1E23fp{|Sw=ieHCK=G`10fkHXyBn1lxYp`oJ3WiUj|3{2KAv5TA_Swj~K1tA3ZX+jSI('
    b'@}X|LG*e#EgYrSyjP6P(w$`@!p(0txsNFBvwoB>8en?oG$N9`2o7;Un$y5=MpqkSx&kg!i7^n~jpy;*w?KR)g*9WhEJvu#m-OE0I'
    b'Ji5Ai{e5?>pB5zQ@EUNXtBc}xoj3xcR67jl;jN^Xa`AKJ!gF4&$bMC86VnJwVZY{HZ$5pQb<}h4vM)cKtA#g;1x4Fyi{nnTy`9xf'
    b'p|zA9k6Uwc#k!Z*`3ZS4XgtU&(xq2wPs-?Yg;GFe-VA<$O%kT_WtuRPi}|Mge|*vZC%f>8=>GDHM4sn0P?xL&%$&*J@8L_S@`Q&2'
    b'2|uf8oE2B5a{Fot_d>6&l++7_pmRO9iVs|0o}84y-A7n#l%iX;kQ=H^uYpn=ybPlb4<85$iy+n_AvI_^!@|?W!Q``bgQR;2kLOO~'
    b'`HfDh(8SaB#i{oJ-4-gIgwuB=uvu!!f%5J1f%2KBgmM#@?gNtD%D%7(Z2E%tLl&oTN$}apI;zn}UbE_Z1$miCOxe%H<mK9ga*>Qf'
    b'1iMA9bY)<X8vvu;$+bcZsx&Q^4}10$?sJrv5R0eepXgHVYnqjDplEB(wgqM)9(u4<{iOWBx8GYkd{>r2I+8piJ!AjPl1&O33^Iy@'
    b'N1=G%L*xywB3wy+TEQ<Ur2D?Vn&EL33-&M0&;En*yZ?UT99<s2Kg6CEn8zb)S2x3ml9=i{?~$aM(2cUagmcBd8{Ee}<tJD2gJFv4'
    b'<Zo{f@mmtne*Urw-fgDO)Yo-FiTZ;==d^%JPWUbj#^mHGE6de&ZB-8H60z~wj=T^pp<{?HtEQCJ6$7hNTtE68%>q@}n7IzwH&Pwv'
    b'0b#HxtH4=fsO9KEfaiR3D-)>IajBYFaecFm#2QWREDCvc6kl;69Hq9o$?M5mN)BJlv1kek1i9T=kCKc=UbRXwz$p6)5Wig`)u_de'
    b'z{Fkn_tZxu-P*9CGDWx4UOJC*4gim`z`8ktN=VW>1&X7<jBPm!QL(L3l$?x=Uf!(W*UyCYQB%qb({`m**r@<$v9!5uhIIl3D3L1;'
    b'Vll?TJ-j488JPcA(evE$tiP=GW5b428aRubzsaIj@(Hn`s{E-o$etNT#dF|-hpFGDi_9&5vdN3DHs<thw1YB>tzxU)mYW2ZhAkC_'
    b'-l1ID|9Lg=C>krsp^%E0_uH@*Om5+;+OH^mtNTzlKpP5sJYA~4{JJc~q?;;dwc}T(4BBxlU{KLJ+cp1^Z_VAsQd|$=>R<YPz4T@$'
    b'*-E7wvfVDfOe&85<*o1PMcVRp=ek=zIo~~<aHpWPkZ|^p+7Ml$O!DTtb!^R<nXdXZWWblVq@*C_7|q*KW!x$n+17~x`)Orj`dB)j'
    b't-n{nV?B*(w*D$b_ISY=y{);`mOUyw(c7lG8^tH3i&{FDTpPq%mndHox2ny@FP#GvVDVh?Wi(6rbdO1Gj$?^f2H&b)CH&D8i7y2='
    b'j>rd)LJr+C0AgcrqfQxOw>jp4|Ktkj<yfJ@`z`NnBA4<t6T7e0v&U8vD|@EfwCX!E$=1=g!tP>LZqtr#w}Aiqty)>Ss>K#VGB%pk'
    b'e{Kk1R%%Ad8p_)g>&Plaq0J)7Y&1)9S-ky)NTFsY^R7_Q^QzYjZ~jD-Uh4lvg#~gFJacL?vov1h`!Y7S<ra=^syj;I%gh%;?Nf@G'
    b')`d08(bKa3zl9wxeOx>nVwgCp{-`n(JNs%f`j4wkmB)%+W$O55_xJHpBFgq=>1pA24p1%KJj+G#=$05S0>Y`C-~FW+z@FGN;Yah<'
    b'c{~arf8ty$Kar9Ww?($yxW=mTIiLs1R@bU9!M>%?yjYtY(0uG;6>;GCz!K5ZCD1ImP9mli*B0E9L*%0wSR^kUDIe1)L|<=Ppygw)'
    b'nYWpKd7G~aNaZD3C(nbRDV*X>t3r^l`ZlMO+U?-$CSszEZS5tXJf*d6M7{=p+q@*LHUO)SXx%hKjMk2pBmdF{uk}T1$|!Dyu?WBs'
    b'ivO(1r>H5q2v{HDzkaNQ6Q^*;{BY!$cYwJDfloz+D9E(7N{+aBBhFW3FDTMcI046-#GdF>$r8NJmv)wKDDax|hf}D$(@Jh9U}Eut'
    b'A}=?pu4%SuDmV~tdn%hj;5XbE6=@8zy$3Hfhhi7Uye%{o<A>!ufiUSFY}L`G!3|RX&_p;#KqZtkeg}u%sd0IT1ap<?`5AuQI#)Z{'
    b'^wNXOIvWti6ZGWxys!~fIG|R?H(1<-N@OH^QuFWqQ|;vsQ}?i8=`VG;D!26=oAS|HnpS(2e6a&!i!pMcTg8O2s3)7~u-R(LK;$!C'
    b'ORyT=uWhVCghA&|vSI~kTAn`Gnle^wyTTh53q0!*RGRy(P;Zr}`chG7Wq4#S%7!Y!mXB`N0ioGu4OAj3<C%UawgJjBPEWK@!A;le'
    b'2FbT&X@V-allmZP+R(C8rPx6x-2r}lqUweQ|ERS?u5aAaQ??MDg3u}+%O<9Lkw~$OXGIRl)#CyP&r$bf!vKC@bXz?T$OrhTeJULY'
    b'M6)HkW1{0KxDBvHl={RUsTHQByvou+b@_yK0~4^Es?n`8<Y`2t1l#Jb({c3dA^rP@YPs5=tI+j5rEmg@_RBM^L@8W(TVu6>=j5iy'
    b'uYIArW;yAtL;ClNEa&>>Q*W|(gRD3%)feqLEdpMxd9|s2O<_C77w6ZPN5|I~L*>qBL(^VyQ<c}Xl$@S55Xkol+v&>oW?iEG6;lpD'
    b'YRja0@aq-!HNxzuJLSLr3nZfBphMs|Bo!S8t9dz&`d|Nr;sn+MAfyF*#kNE&QGopw-VbXJb2307foyOm*u5I<GLS3_u#p1=Ta*fn'
    b'6<~vO9TDy)m}U_nltr@XDX-v^$o0*ULS}4~;%+?zN@*sTj#=WCzH%PpVgP75Qlu$}i^M_y)vL3U-;R#|!?c_aC)e*U-Z^}XE4<`h'
    b'Us-zp16$yVFW;dkzIN|EMqq<2_-{CqcT$I5z>1t<fr<BN@)10qTrJ(lPqJhB#q0w1i5EWxBlvVi`+M;)!z>)wf0e`C6agXVvGT%>'
    b'*k7?}<j0eE2EXC5J*K!_GQ0-<QMA`SK_zhJdZ0vq45E0TjF|yf_rN2U%%v9MaY9+g8M?<V*q4A>2x#4(BMn}y7GHn{6I#PFbjOe0'
    b'9?@m^$BTuiGR<A~CbZX%{Jh9t&D?o%A1^;*iaC!a98Z|LNG{oz7_9p%OvHOje0(&c2;HS9tM~IK0Cd8FYk7g>l6R~;gZF6RFS$*I'
    b'$2r${<@_?9pr=RDE%_5*&wUzG(|N6g<YETo&cAHuz!yXDH+=OS3tezx&ZCK-2z;C^h$YhnCfYv=;`x%6{^z59CZ7O2-?60|O|E#m'
    b'F<ft?0FE(=m?M7?C&^h9GE^$Z!ukIBGr*48wAe@(LdHmLm14%y2G{pM+I%OdIx;cu&qx0}UQFG|uP!Cyd~`wC(DQsRkPR`A@;e?u'
    b'fIvb0e}Pw@em2$@=xvZ(A$B|pK!1|1!8a13rP<@rWO5Yz!^Ph2AH+S!Kf!{N%qY~x7K{HbX32THJet7N&SEeF-YvlIO-bcqMl8$e'
    b'{^w8Qieade1xPX{6D(zO#_nAI@d~GMDXt&>ioAdm7QFo@KpTI}Eo34sl~1$81)G!>{)8IYBNZWY%$7&1<vmzt%g1NNKkMdIwt;Bt'
    b'GpsYyklRw66W=~Axq<ZwY}g5CCom`@;DBii=3ySyO~!c|f~h@tyaG(8ge6B3=$4&v`yXC=W~@FgVoWQ<1s5gi!LG+%JdYV_M?N}v'
    b'6BdAIBRPgod#?Xkyzw_I`3BqmnN~5A<IBZkJ+@*{B$DUCF>PytPYF5japg^-<en5H66gXq*qv33(jST#KUWt@?Gkx-mPp+O{Bd<3'
    b'KO{c|FTDB&tebAAcv7t0yC@-7{Q`8>3RoSb?PB_}D4v3Fh}=o;8L?WxuzW*5fSCi*lPol#HZJB*m%m3KZB|R18U==52wx;L@#8V|'
    b'aTEkdH9N1|DLe8h=EH6D%%prV1kc$6Nmg2>kBcbIa|HK%E*W?jv!Y%5LviBX7|V;29D7JLctogUJmkd?6PHL~LD*8R7+?^ulF1`-'
    b'$HaYP!O!5_PcxTm(|@wy*quyJ5{q~SrkacQ_;!+Ro-JP*K?(}isS4QA4=7fEEs0~vH~BQfP#8)Yz%_U=G=IOxeCIhZAz*bL&xDR3'
    b'r<w42%dkz&rvyVOU!R9drIjP>q1oO0>+6phN+sWiOA#R{-mhlC0yIhdKnn{y8&0CT`{l*rViL6RM)Q~(A`9lHu*wS9<qU)gCa68;'
    b'bTB>0xkf%NgtAmDKMhxa4BBkDAghlE6&-|Jyh^s}A@oadeiqh+@SAktDIUbD1HcrH-X8sm$ME2@p(45zw>Ewj!mz~AY()!-qwsD<'
    b'wCbG0`09c>f4f>@0C(cfg}F<DfuG&}9Na<I{Ea<6#EXE$fDrbn_y@>~$Dd6QXkkl#h0_6uc}cn4%&e->U!w(9<hx@nw)u}oUHovg'
    b'6cP;)678G7X`tTb$q}|O6A}Y|*ERhoqbmbXf>yE0)9E|pyT7C2J(<pzk41U+v+zYjGbP`L-`I@t7>NiPgR&6uK^Y-_7DPqitO}aH'
    b'PU45WCrJh{4;%nrVfF-)D=IH^hN8O}Y`9oQe7zhlSU1WOa67)ok|gX5Z^)p&2bI9JLRGi^U`#|D8rBD;VDR1rhfIdwnjEnoj?#po'
    b'PT|)06+b{>xs9U)NWkedp~waGB7HIJ&LVF?!UNGEA5or4mQ=fNZm(9}G+MqOg1G?RTQG*xLq6{AP@2rUtfa;ZA|@;#4BjMfV^GsR'
    b'Hz(+zfaAC;Hr-dRL=KsuwI2F5%eX5nj{_F=KllNBUXEY}#fNAXQ8pu6Fy03<rOc0Pk;F51LjK0$Gh34ICU|R1qPDTO6w%G-H`vQ$'
    b'?q`t~q>ig7V1DVC<0m1VGn`9om9yyRutS`;BBY;>_pvP6dqJ(4u<7PkoWKX3x%VsOTXEA9L(VXvwWjAwpe?M<4<Iz~4kcNlBH(^?'
    b'?}FL%?)u_lkqgZx9~re&mzv_|Pl1f0)aDdt?I4`-Sb)!tGvsxA$Ea-e&&OC~%Di<G2J8EG9#bK;c8-qt#Qn;Gw~yEH1dOVg+@s@o'
    b'vYO8R1T6Y1V-##TP5#an9w0s~(L6s2o^dJv^YQ)QPOx(yEGZ^20A&!3aH0^#|1qW5<DPs3zaVlaNJ@Vq%;f?L8lVNvf^kPPs(<?s'
    b'fnCY&+zHI_&wx8BL}?+N#X#=peI-W=9xq$O(+g1=56{Q4onQ<9PeL}SM*rY07tz;Ka2pmV0J+i^VfQOhIrL|vn}ri(JP*Bd^uzFt'
    b'-zlkq@{G`Z{}bR_^$<DU==su3N|+EjnWyjmBpN>FlIO!t;tYn14Lpw|in&<ujLkobEhzAldL9pOQH#rCxJ5iC5yH)siv@i^QTZpp'
    b'T(BE=yFOxeG4=JL06$nMbe)Sc=+8%%6D(0Q-baxN=V}>ECW11!byYM?{sf3)R$@NV`}PR4(|jWFGv<C_sWA?M1-$b=3*u>1vUK*H'
    b'YIk7@QY=zN*U$%jI_h0a%%;2cdw*3ryaZfNq-cxFf9XfO)zMS<^%(h6c3Gw?eOTRcPT!rJU!Pu|lK=Wm#agqKAQ`x%?C-!00+Rz+'
    b'!Vl_3CG14)t+5^${?ODcV;ls=c&J(S$anqF5A2btjctA8+sp{`!1e=I(}scT`(fY>0)M32W-#1puz|(KmaAJ#AK8Pksk7n8&`dUf'
    b'!9C`gA@he83&UV5pxRKgt$}W8Lw)S&K`<D4BR{mfk*@oiYx^M!$G&X?TzwF_njMVY;mEV?f$5t5U=(gQ*vN;Ov+=+PhOj>7z#b2n'
    b'7O+qs>z>B6p%skBn(Gret8`VTvS&n2yKR^{2u35@@&>vU>O<WKHQ28}_Xa~d)WTtCc)IIqIvbff?36dQLUS<k4Ndb|$P6~tw;0L`'
    b'LIiGj%rp&)8N+~$ea#vTtdVJ2=9t-@7wF8`0;D@OY#sL89gj2}cE%i<0AuVLo}mq_Ft9_<b8RoQTz~9&K#4{;vV5F{=Xv_T-DaUi'
    b'gF&dlCJ(~_tcK<eMpoc5Z=iYpK-UMu02j_5@r}A<{4#K|PuXPAKQThq|LS8S>)Bnh-8QK<8@nURWV-1aV>bYL7<ndxof`rJShlGL'
    b'zyhIf4SaW`YoTY31Ak!K!NAhSV?cG|fq;c9Lkqmoa2#j=1NhW(ZQEl&4b~t4ju^q%{>DtIjzY^a0?QqQz#Svo*T?Q)sQIR@yV}UM'
    b'#{nQ~ni{ZhIDn-b3_(l`ENg55^M>QGwedh~$iiVT(gV%2i~)$C@o4BX-**iSnb<RjuEhrWm~W4i%{&-%j2BP2%y*W8xj>WxQ&DFG'
    b'hOIJ$l*X2YxOYd}FnQxYRA1vy1V<ekF6@jx8iFA6flI@1=!HW&unm`)3^+gs*#wk68i#gZfoRglK$@mL(10)k-+Y!;QGGTJjnEz&'
    b'`j7#sxCTfee-w^&8`u|wu4jz>AseycUhbf0pKB+dXZ@cCit52?jmN=o;0-m?3ScKu&a$EBYYeu^(={*jjlsaTy|EA51_C_{fbRnk'
    b'jAP*ZXIKxF4Mq$^k2M1FaShlqpXq~f2<j8-#={Txa12x>xRI_~@d|$X@*ZBE{dh^{$EWb#Zfm>STdF+>%rVfbp^r>23_@c7A5E|s'
    b'fPp{`1->-|^I<p`4M)DOhZY;ba%i3nQg<8}Y@qHkrf!e500bYHUZG)|rW-OFblzxWSmRNk8_cyV4PaMRoOeL}G0Xl`x_-i|sxbn6'
    b'sTpVx8X&?nV>om}5FHv=nXp7|0A`QxX`n!dt_z!F*dA=0tutG*{jssLEK@-Z4PB6!)>sQQ*MvQRzcny^d}HK|4Brn13@obQI^th&'
    b'x1+odA9g}abu}2+4Ts}_HXQp_5Ljc+8V~ef1fs$W!Gy3!7Fb}OI}Cwlblm`p5KJ4x8~B!QSi6lH24GZLI+!J3T7ocgVMB(#J2VH3'
    b'>EUn~7#au#-QNwmW!VFRfzCGumJN$*S>|vA_MWAIvbO@TrM=MbE$}J^A#D1X`GbMS{1DjE4u)*UISq!o7chIoj1W8yeLNi5USOE^'
    b'P$OSPcZZ-R19!9$t3B%`3kARiV5h=X>S4gpCouxBTw&Ws0q(5^<{?<}L;Mve5&q>_q3wZTHy+ri&z~@~36|o}0DB%59E2OJwV@fl'
    b't_?#l986=NnE_b;zW;<FfK5T3jfUWZnKqEI!EEqF&;|!GX4crSd@$@swx$hSa4En&)W%@$j|MK#gJ$bb7+Tk0!3Ja4{Lo;51&(H*'
    b'f&6A8Z3J_&z<7quXTG;)<LCUC%Sj$*%X_wrd<VDQy<^Wv1V!BdP9_Tn{=oFXi$$?C2AjY#z*`=Iv*g3xj9eEya!&(iZ@_?w!qM1w'
    b'2f7d9!3v%Ujp4vBEo(S%HOprn*o|Y@Ms!d>6ON2=IJSNGufd*axKRMR&cN8wOcz`MV`PIJX@Z)xY&RT$xEPotFC2s;uw>m3B#9OR'
    b'je4Fo1Ycq}7(WvlMraxCU|<bLV|xTs9Wt=8yucfqLu=%@$fDo{y9I5qSk3go$YFE`2@7omnAwwHWjAtIc*(z=Nkp~uu?9-c2*;KN'
    b'%U}$^4g|-11m>Ry9)M?4gkxX~K{5m;c-T64pCeq&&^N*L-)T_a^hW>@mfs(E9;!t<4E3R@8-eFrE(6~Kq_}151e}5V3Q*)}rac&;'
    b'm#LvmI{>ApY5rIn2V*m|LHmV)t^>Pjx@Q>LKt~l}fNQ(cpe_hcV4cBO4`FdkkZ$0XfVF1~wGkp>hdSsaw#n9R&+@A4f%|NLG#Y{$'
    b'(ok}Hf#nT>yL2yP;}K#qW~MbT+!5dsST=~^f$jQ+3BI;A+I%Dy>R>!+=sWoSAPh$!QuX231WTT27L3O%A51B>1@41^W{toe@zEJ!'
    b'HgKM=4?_*MVhkQUgXw^%8U$dpfK3Y?s0$862=<8yW}0nmu0PZP2AxbKW)FDV7-MWew+FsA^v8g;YmV5^0v)w3E->e5^0Z^rFLp&G'
    b'aHcUB%5FeKl(Oi+GYM`!gFp|!XBdo!?$8cxdlZ`B%K4^Y4#10Z;d|U!Hr9ZiJs|4<d<gK%-H`=UFo3B(CoV1;&nyT6Jsh*4I{-r&'
    b'^o0(7qy>YU+Rz*6U`Y?3b^f6?3P5IP9%zkV1O|!*1n05=7}zjn!_ZBTAOT1&KLkl1gkbRu!L|omKpz@I{W);~iU(J1I1a$jgyna&'
    b'A=-LKKei3}610k~>)z1f)Pw<cd9U&9Dj`Pa_eysP)`H>5%+Rwjq;3H}x<l}+eccT-hTLMfJ~(}$4?+}loNij<p+5p!9|R#Ag@duV'
    b'xgJ-ofel`%F%Eo<5y@#FS3)pybsW%#4`^~5o5xR89puJ%;G&xW+X;F^*L;k@GQ$Ns!voRmS?1Vg?qFzH0}v}lpo6dM*|4B6D{Twh'
    b'O;{F?%bFhAFb7==P|KQ39{~9bhhSv@SB%ZkI*y-;opX2@8z;aUsiHLKGcvl$#^FFWFjxYj6s#bh4FPeml{EvXS_eu4N67<zW~0Fn'
    b'L^wPjSVMh0Fo6xhrg#PvU<)+M3WkOOqzrZ#Xhy^HLy*E?kcA9vY)~nN?mx$DK}Gpsu@3{=)_|Y`a~xoZ9tMQT`!EW)n?q)RhX$6}'
    b'*fe0?@GLlyLqKr&43b3+Y><n-HF9B*Ll;<T3}gx3oIV(Y2H1tZ>$|YL1GW48)vI@>N57q4TwR|Yo4k@BrhcmZyJ&g8^7dt!;bdR5'
    b'Jmc*NSkQl*PGrGcpeOOI!=K73GRfM_nQ`Eho<&OQ)i@J1k9A8`Gi^(fbz`l}*RNm8%kPRinJDoDyHtK*=#5Z~B)q7HX*O7;h)OZ}'
    b'F{Y`)2Qi3lDR_@?(FahxX59b6=uzbJ66a|Zx#ZsMEZm1eLmOUqvA#MMJese7)dm`mIX8u^cRV#MgNGf{v8*G$n^oR|A3UsqiDfyr'
    b'z~bw4lGVi*W$_O&epN-Qlk2ZSC9M+P0Y&1IR)?n+DTS^p#Xd(*Z^2T8x4s<<B2(;bqW+thEH-Mv0*Y8COnfB@C#t!AEr@NYL(AIk'
    b'E^4+pSy{p``nn_=ERHKB2LDxg#}<qVcKb}>Cvi$lNj8s(g1rcphkLN*l&Slf%8CJD3wV7c%bCRQXE~r~`y~o5eg_}!RugxzhgP9N'
    b'RsP>7vzVUQ=k&6VJ=Yho0O4vz+^$3k)sVw-Vrjzw+0qE)N?VJhIm{>edZ<di-}5Dt@8w#!@G5ZuU67uw=2^p}zR$nuzH05O)W`kL'
    b'p1}+RtYrHwSI3f9sO2?Ia|Lll?PK05E!WM1K=fC0OeXBqr6P3eA6-8pSIZ2mbz{TjBwvWI2#QOAtLr0>;?CvC$D>nG6?UT+G7Z36'
    b'KE6G>czabW-nd{BlER1~K`M9iuIY^`-)VZXkC)14vR4)VkQ`!B!XB@O=ft1sW494Pz5|8muA3WJv=HGx=Q>eH*$HT7+?Ey-gvE|v'
    b'b$G@2Ue-0M(w_WZl}omV&mx0ilQ7~kDiNv#vA?1YHB<ba7X$>Ili&gd4C7<?V^&QtV;2A@i@uXaDHKsmk;#=&e3lB1FlxERVnM;w'
    b'lv*q=Ou2u8$WL`lOLT|xB8mzo&U~^;oZLD%hL#mmojf|WRTg)(wTc_c6?S`yX?5FQZMyXW?;2X|yT7_1=mD)|<FLyAt>Dj%pfj+t'
    b'AS~`PHJfXK32LGdT>AvSO}WzPDGrrt79(N{Y&*9&Lei&rbQZEB6_)c|NTCOUr?vHFqrsZi`cC_JIwET%FUu-3;Ar(ywA&_2WuQ5c'
    b'{(AcFC-15|x&f4%N|V#p`NG=Vm}XDW;eW%niQEXxe!IN*^zrKE^DWvLX=lbxQz6{$#si3bo3^4`-%hpL;%D5{lg|d2bl{zNSH4a4'
    b'eg%<%<s^QbfqH=No0+f~G1~4X4s5}$rDAMD1zk~)wqS%|ncBuKCCv5joj7zr31E{;vCa;d<__4%PQbu|6&*_=`2S@hn`RP2lqFv7'
    b'ak5W}ZB{w(o;3VmF}If>MRCuqE*Ob}E?U>+rXwBxv>ZR((LB=C+U@yYZ;BA|-GS&SFnYuS=JdK4E#DZdClFs(p_v0aEUw$30C>>W'
    b'wv5wH8}5DhAO`3bN~eq6IebzEPYcIM8=+x^q}|iPPESvzY2mrTnpM-3)pP+{5d1bhQ1pT<Y9i<Fwfs0^4}y?HC!i#?@0>+e-YIJ>'
    b'RL_mVm8g*jYuIu#=F2xr=%|Z)*(pUOy!M15?xpPv_JlcA*RyYZeelXFygGZ<Mj+oxwc1buT$MwxYJme6IUS$xXqoAG6c{<P0-a~U'
    b'EUjG|@~cqa2eaHk^QQboA8pL9k~MEr;fCHfUD8nNyI!JWmZ7`ZOO>%vA9lLypUoDEzk=<xChpV=TxD^PU$}LxCJJ<N&^$9~(zVH@'
    b'#)=a4ohY`NB_1h#A@_HaCKDyWy?KX;TAb*Ws;8G$jjwZLQaMu4;E5v|&N$+dg3Nu0rkLmOB@MCcAWEKBZxow7bJ*#R(o2H}@VSEG'
    b's1<F_=28tKEtx^FNG%G~kvIBniv-NIi^;mM)NE;OmzR3VcTr-=*`^&*Ix0r4C{#+=VhAu7i`yy^FJN)<4xC1qjs09UKpcQ|)IVlb'
    b'q`P1t{xQpk5zByRd-L%U4E;Wb<|wOyRD%=)W<m{!fEPwkxvf&@S(b%8+-H{#m+TIdK_()AxX^3`x9h)GZ1Si`!&7~d>{z?(ax2SX'
    b'1|^JGF`?NVpKeEjfN_FFjL~Ln_%(C*)hFJHhR`UBm@PK(c|}dr)*mW2+Y-pXNCLUtrZv#3Z8ogVzbkDDb=NRWc$rt#alCkW@5mFP'
    b'LJW)d(V!lkOOT?|q`WJ;G_0?U?Z`ufo?@EWPTs|!Wxq}*J^mN(fh<`ncXZRO^bARVX&<)iLK77BC87(Zo!a4hN_t+TbxZi}s8ocQ'
    b'N0ORW&Q<v7%)dyTb6W~%lFSeItHmezG0rrz@hYH;uu`qm0*oVyXH)I4#7R=NW4Q%P6;*l5Zo~|0c2oY;+`Af2sE`gjuc|r>ws0>~'
    b'zZvoHueycpt<jGimH(83kx@p4?gY?UILK-3m}~_O=Y`8r098KBOr7`*Cn*4CGc4|9Ga{h2_o&R;UeVc0QIo{F1uji6o7X=bq<I6j'
    b'!t`nIGfOWAJ^iu<eD+%jez(@N>?wSUIGdp!LN+*faUY~zj^=PINYBz~ob299_OgyaeXuJHv!~EGMP2L6!i+KihuNRoPv>bWAvbcS'
    b'c0~iU>JiYE-QddaRod`T$g#1juWeOM3(Mn|&$}i89(AQ{1XJ5>HNRV6^AxcE;8(ENMJsD;U%0|j7<ZdYHQxmq7AH5qr?-<s)N$)_'
    b'N>%9Orl>M1ygn}jO07$4iV&#XHD-()70=wtc0uY1V(;i=xo2AF3&Kxexa}?Dr90WP^IuW(Yu@Qnd?R-ozb)H^@H(p)$F<Gn>Csx!'
    b'5x-Oj$FvGwX@)<y3UYKsnwYP;09I~>TzNFZgvOF9So2&3FT-qniW}(PWT5E)cVFcd8Q_EZ5jQSSzh`EQ9QU@i89D9SF8k7gy=gY~'
    b'J+Fb=1h%kvn;YT$te@9P!34Jb^zbNSQ0x*q<7KA6m0a*D$&?T93pjSaqz@jHpz@$Jf}%u$gm+S+3<fOGiI%QQ3$CR81vV~5zyKGS'
    b'zyECQtk;V7f@mR{ZE9}a8i<b)=}!fC5+=^eQn*i$g**Bbjlm~rKjWYEhR_zl_gVpy69U!9dz~0)4!@UJdbg;1dlaoWL~A6s7@L+0'
    b'*%p@O0*AuVSK{$);$+(f?O)o=D=<$QgV=z5WMEmhs0DElxp%WT!Ao_fbMJl;X)}db1Yb**tWBd4NWMS40xmf{K04zGV8<69KAc_y'
    b')ti<#G)Dd~Fh_nk9NS~pAK50e?D1e=7=dZA;dn4MUA4RQ7}u94*el&MH9x@XQi183+Q1$&+xP6DZ7}BB1I=cp>y8aQXd7V(jzF5z'
    b'#?#(<N+qqi7Qkt8I)l|hbG5FidQTzPn?*(nZ<acz*Bst1o8HT15f$?Y*CZy@f)iOu)zzp?NBX9I_+yEI<vGa}O5dow`n~d|Oe;*_'
    b'qe#XrfPp!|FFAo+m{&hqvS}efuXTfRgmiRvcJcekJLmZQ(fMyD+wE2}7~Hz?W?R<^WP`k;oDp)Lc0Y4GY+8v;s3(&c(?5OD1@gA1'
    b'<kOv625-ZDHSK&Y*zUOHJY(l8ZqY{TV{J9U(e@*lWibegk%~f}Hzwr~bu0-+lJPEDQb91@nLQ^DCy$PY<uj{CaSx?%Y&w8k@wU{i'
    b'V)iag3;>oksmP7p4YE0k8J`F;m+YDL+Lmy|ij`A3yW5;M&UrCTk^lnyf+02LPBmxq)iUYi8c-LHJH+!j2w6~|xTei8>KRP{hM9lc'
    b'N}8ZqBjpjAARpB4r63B=x5fo7YVh>HG|kUmV`Ae&hxo5eGKpwXU@^gbIP}cf>S1MrTmih?7f9DzUJO$61@kD$FfEyfpYB()&q;nw'
    b')~Q!mj?abU#UFz8h7;&+ayDB>9yhq=HMtc0oHgYH%IU&KdrC)~oYMw3WR!2f)h=#1(Ntktx0?b<?*J8`&|=)y+Vmx>8d%^+Z8_PL'
    b'>J~5b@Vg1cUA^t@@NN@&^@bw8$jK7(UvIZLCeH!G8v_Mcn+`7|4X2P)(26TAPU$iRj?km)QyYTMD4{Tp+|F$myFwXlP~|q%I~Ky{'
    b'bJBP^Ofg;r4E=M|tHN1vP*RF4y0+8jO>^bivpss40Vc4ZtZ3c^V^4}qk?oY#kFFCS{2}6$Jy_Z7J^qyxh2Tgp+`Z52F`r(CA4~Fl'
    b'%j5`QUZj3~vvIMx7mhId^LSoL@F;rQ*(x>waH+g<DfJnD0cF{3gPd(i1LOrGZfQlYu$A?2C=w@AMMP21PczAa;$mi9N?L77oCsw$'
    b'kCcx+9H~NhmVY7}LfrTJuzu8x>RJXassbEdQ<Yy7+uRU5QSe&$oc&Yirq%*I<AoNm5fyXifff|Euht9cfKBSr`f=gQos#{qH%eB='
    b'2q-Yk8&1U_!_aiz1KCjmlAYOL#cpuD4qty&HDU7C<7%_{+V0RH2)Z0RQ@a}*y-z<j+|)x@gL*f2HSb7Cc!B(IHBmy!oy&4EmH8t6'
    b'!V-mcJ9j~KD*Cc04{nmWH2p2pV%AIsy=T4R+y;0+NQqFnlfwnWd)@E@f}6O})R_Z53}+QD68x4doF|aqX0FshSy4&9>R%d+N}reb'
    b'XFryR%USb$vGxROW^Ra7{o+&60eYV7`G$ymqvo$9LlPsc$%ik^uig+w5}x7q=UBP+!6rW90J_aV_M*<J@ka7_oC2B<5oD>h4S-9R'
    b'U7l!26g+73{E#&1(elzBv^tCOow`KSCTxpZGe>AG#}g$RKR=A8svC~cpz_Ou6t{vFzF~~k6BXe?@dIKG8qb7NZyY`Vq2Z-1icfvN'
    b'-Qb)h)f_LB&c7+;lLjfuWk4+oBMiZ&aWLr(iiFTK7c?iD%K~|)_!>W{tPNSU1uQGFx)=ud7qVhEl-PAKkz7=)r{u2OXJ5C)Nbn&0'
    b'aAVK<)n*Pg00r`?4ff>Fy1mhFH-Sj3vMETT1QOXrh7JYml<!ZG*5X1M^;S+y)1=dkPkdd-RrNM^d%#oa0!3^1ivz8PP{T?*g`#?3'
    b'U3ad_pRH<v;`dKd1Pu}+Phw9wk!>P7K7*bj(aNgtxG-2WW0bMA2&(oLPY}CNbxpHPQ^~6DpqXUkkHgB=&i1xgHLQJ`t6{+wQTUiE'
    b'yDCu^wJgL0YARV^uWHIFxr>$x<yeAAyu@-YDX=$%(iL3P^0^AIiknMC!safp%J2k-i(XS&CZ?|(O(u#kWE4{CB4>s_hq6PKtI3td'
    b'h*!%wWk_T3B3>;>4Bh1yV>Ir&3v^^@p2~403hgP@egdtg-tk-alVoqXU=(-S`={Dd+E1<b_TZ6U>W+ABb2qp{McfhVhyi=zE<Bmz'
    b'0Ki?`!DjsO%jXCDtM2+jUOc5h%JWzw)(T@*RiYqYzPK9~6A?4RT-_*O4#TSV%R}*P7ju+=&tmwyTvY^H-set<IK@gemeOmh3s{+<'
    b'7^?5nAt5H|RBl<NS)4e2Lm)KA=t8?w>QZV1AhA<K6o(1HXhgq_w|sJ3F9BNK!4;F#DlN6LuvvGSEf|1%l|{p-Q5qEGz;k<rO-Bu$'
    b'8}OW4n(tql1g2RMn7f#is@#}8m-q4Aqk=-<?mfZIY+O#5SRI+xo7TA-mrqa_wb64P8O);Em@w#4r(8u%9;bloXR5R(<Xr33%51~<'
    b'X|^D<R}F60h6!W>s>~eA?!whQxOq@J4_d^w*MV;GdU7{~sD9I-@~zc(%rE*ubw_2ywYa72XP5b%JE-1S6=UEI!e2wnT5k_#+rI{$'
    b'p}{|!z#|%J2Bt_N)J%k^2$E|9`~3#D`nGLvZ*YJ4o&I!tc^ZGZU$w9QNEdWB@vz%f#&z<%R;H?Yo&rlJDdGs_w&mt~Ip;=Z+mJFO'
    b'eeZ~LX9o-oto_Md0JIOEc0#y$d>o$+vHNC^WERTBP9=LloUFh$cS@-cf=9c5>R2GUKQu?Ac$j51SV#-rT0X8BiMo1n8?g_ebV&b('
    b'mHnfhM_TO2HF-?1J?Xrf;cs%+TY4K}>Pm+K6#qjVB-Kr?YL#O9>+438xrZvOW2(QyD;&DOHI68>$+-#aaC+*0??a{44Ao6%<3l8A'
    b'w@LG%Ru~sH^x}#O%I7{`N+NH<FBli%gn+t()fPJWZ)N!fn64m&J+U=vEztJ*3wg*wUpvdVBi`M5De1-n4Yen=|4%%st0f4zEVVyw'
    b'5vI+K&z#u`e6w6EmUI=H&X<q;u&gFGl+A!~d=~s~a*kH3?8+H<g@XlBd4-g`(y74uWV((BXZD)U0c!H(c#XF2xBtIp{Xbc=hOW0D'
    b'&n!@KjQ3nRRaAVxx~FXTW1%A7Vm`OKh~R~$%I{ftr;sh44vdSB%2u?ba=g`&=XPL?`UG2gXK|pYDY8>3MBlGg?S5iR?TA(%q#&(#'
    b'M?DsXOfH>)7a0bGkn5D+qNO4xrFPc^6?Z9&Njp<}lQ@eU1E<gurr$KKLJ+|k#0jv;muP|2guki3onF8H^cD#fg^bJ1^Y2wE-Fhuk'
    b'Y_@{c5Tq=@&Um7uzE3Z6q^Ac;YT8hARDRubQ-2N5wGPm%#)SuoJJaFu;0AFkfeJhvjI3fJ%FO4CQ&s#$o+C!W3mNb*HTL2eH^l@N'
    b'3Z;rb9S@-T8C&vt;F3F^gZ%)VAX;R$t}1ZDRu@^01dt)xer2Krl62mkULIlx0}iOmzdSvEck=Jfucv1x^jjG=g)8y}SO6j=a3YaA'
    b'7jOR`SVaU3|GBvQ4<IROsPLxv*wNYb$>sUc^-1{!FfQaPS?qV^!D8bY_hH*R=?O<9>I?7fc`mOyy!YQo!r6pwdpPVN{IADPE=twc'
    b')5+0_b%j+%N?zq44$`g@0whHp^2uaKA@EyAoPB`Iamzg<a^d>iTzIH~pHifgA}F`0$>7^V1eQ*rn<gdnu_bvvV;09(QB-C}K6_*$'
    b's?T~S=6O!+4;xPGH$O^mJHVHv`Wuh$t42#4;lQ+pn31%{r6sN617FJowjPhOX>;)?ef<>&09v22Ua2aH<MQi<dz`muNDw3Z4<Ed4'
    b'7J)@C;-fsWnSmFR%xfd$Q#m6dX-*dTY{F|0LwFeKQZ4LB<b#S0BG4oWMrn~u6Skx%XOHx-t5Ck4vcz^7wByXQynX><Z7YCBdF%;H'
    b'6iqO5@hjuk{ecgH6)zPKf{#Ok^*2|loT(?wU2vxEwJE&1Q%_h$u~zF$ihNe&hR1uQ<E!V(bwLB7){Cmh06Do=PoVW@<g^wJX}<aM'
    b'+{{r(C~W4BjgvOEBhVU`WP6$|=AEpus>ER-?>>Sj*r^?~-l$rCgq^xF)LiM3B=lQe>aneTm9+N<gYiJ&a-G}OD3J0ZBo0MF^ISB%'
    b'3Zxs5YhZ;yaedBC&rh!C#y9rx6LlT0!ScGhU%q1@8Vh)?{e)(I*<n%O8=fCfS86*L8HOEr*sjzL!lBQG_Gsk0o<B4U!yE&t+NP`P'
    b'W?+tnhHlscFW8|^t*YtXc*yL~wLCxc0@r5D9NPYfVY_c%AKC-k_l#kXwJ{V+a6<b5<|H>uKStn1JZ1i>?rE-RYrbz=fP?4SV~-iu'
    b'V62TzE!0ON&jXUf?v92DzX!u%pjm?;3_N4xxt6<a^E=fJ$FO|9JFtzw^-V4CLSJ{WgXL&!4t;$va81)6ct56PYY0SYo7ns=9E}5i'
    b'Fc@m)kc|w>fa#jU(AC_~2u)iz4bu<CuB$V9Ffx73AHefwxcNw)1;pZdMi>Tc43q@Gf`L15L)hdIGqn*cr{Q_tOLiUhhDI><bj>gW'
    b'*9|<&7{X!)45q5-Ln|;1Uo$P;_H=AMZTr^1*RaXA76e0gIP~nD1_h9~&feG^`vcn=Tl&~Q&N6LdXt*BmQD_?0$oup5e+|cDY)c)O'
    b'W?&3F-*x>!Gq6Q2&}(RWK5#{-1=e_M4u-lr3N;J6lVd585l{j1pA#34nam3UHuA;;+&Clj^wD78>wwI_8jr#eU<53jCo6xl@*IB!'
    b'qIL?3IglOAo@dq6k>=T<H@3#M&O*R|xwh@Pn!z+}q>l%%1VL!HY&fztcfbar8w_n`0c8QN8OC^*ev+!CF-!LXe>il<gW*6kZEP|<'
    b'8t8*y0G6ya9D^w_wB2<yg;BvfT#7~PPVt-z^wB~z|9U1ug7pba-ve0>vNZ^8hW%Gfm$}0Lgiv5;VKBCafju095&+aqO?S<4V0a_V'
    b'w?aL1pNxPvG&Ss0JPJ&AsG;EXMmF;d7t7dSuUB6iTO$_cNha6lQW_2kR#~RfJxoSDp1eq^>jOItOx+KSkv4Gc5vqVOV>b30^}KPQ'
    b'*&b|bFo5mVUCR!}p^l=I1wrV6#@cycYXGYff(kQySY*=}g~L(cngb2HDl>018o<zQXg4hiveeuKYxB{;+G=;A?!LDQz_fl2;!#06'
    b'7(-VBu7(W)OG5|K0K0R8(O}wxp&f!M2BG6wpfPpBcSG!AJ2XRP04W*fQ@YZs=7@oI8iA-DSeicsb?ps@wuX(Bb<i6D1M9#an@y`z'
    b')m#o`+d5?6%hfp&p&=0<YUk8Da3|b}lYsq=$JQy|GHRCk_`Gso)&0N)Q8pTZWis*udteMb;1JjV&}2X<z6(kbB&~0ZLADJ8Y(DRq'
    b'W6jb6Y<e9&4;F)=<uRrQnx_rI0qPu3I$(Bb?g+S-fu%Mcnbv5yR?0QV|CdmnB!G0r225wJZyUZ1Vn-W~?182O;{maP%(ivQAG#xV'
    b'WH6tBx(EWW1#OpUU?_oVduDV3%hd<A4#qy1f?(-_IX`wSYXri0V8ZT!fp6ND?@{+*853-4b}E8_8wGnyIT%zLEp^MuIdf*1UQ10Z'
    b'DFThvEQ6S5F!4+#;DR|e`e2*ZPb(HpLr0DIBhZqzJ9JI3B5XD`*?0spb)<v&FdQ&23d0SGrsZ?aK^noP>7E;U%mR?QZ-G6)z*_Q$'
    b'mS)&P&ji!59c(U|LQ8=O<Pp#Rs?1~yFcc3c0YR+mYmD&#O)(=fcaq-WzxNae{=bV(IE|k=t@1RzxeQra#4Hb(XUlHZt@>4S-s5w0'
    b'vEHme*|t@;vZ`cHEk(Ab?${Q^#%{h=s(zK;#;{#Yv9PwDU^n>44mz>Ed*OM!Je?8AY})d?VHq~8PgvKaR}`-66bZfiqYK%!RiEpX'
    b'@}3Lw;$Vx)ki8l(B71oA;*TXDWdc3ev@YKF^&)po+C*D3J#e@{yD>`}8Jek&Z4~z4=QBfh1I--SmK9oH+}VL=gEbC5ls|G!(;eGj'
    b'{ek)(tM#dTom~vTrjj^2SlZ3;e$G2wY}eMi+v3IguGQ<`dwcQeJl7Ss+`mQK&XqYJbN6u)y8*w)yG)#ATqv9h_V>;uJz7fOB^2?M'
    b'hjPzQ08bo_)GJ1L60)Z7UB0z>9>1pZm1<eMHzGT<xkB1=7S4NO8M=)s#uXQ|sa9MCwW?+M)RJ#ih|f^}?Zf)|Z>{qwml&&Ct;#Ly'
    b't*5xrD8|NB-8Q^y-cw2g?^b+n(@J)2a!oS)^L8_?CT*2U9k{b7<S{#{Kl6Ym(oTBZ>a0LQE?&Ow8w`j^R@>EmYpwfIC<j+81czIe'
    b'6@;VI%k68xy{Qy_YY?yN%fD@1?(O-?yKP?1t*}D}8<cO`wr*Qfowl`A%=iW#Y+Sdj(70nox8>4TvuX}9MFpVz<xr{A*C8>HzK8I#'
    b'%W-&XTy<1_TOCz_-1a`~mvDcOFuUp9^{i@J$2QxaHnrj|@qFb5QC^q4+?1)@UX-onNIvC>n%rZab^OHJ2syb|U-Bi*mFE&C@5A)+'
    b'zDTd?Q#`HqW6Jy0vfgQ`xqOCy@lt!2L#UWx{=6GmlU<RGtY8Rk$(X1C`IMcmE8i!Ld`cNicrI#IDm=Z#FRxua;kMONP3dw<(3{N~'
    b'@=6%BjYYRA;8(~|;`fHc0;?PDs=QanCoU6I2&IiSb~D!~o$)po%W5XqdcSNt*|Ry~F?Jx48=BoDqmStoGLe6#g8e|x*EfxQ!-3?k'
    b'htb2kF30m-4BK@d<!rOhEgf@fuR(Fq-c~F8;K#N(uIKp5<)eHmT&4sH%ALL~YImGYgM!~lQ8ePa!#$+}L2a%~3IR|VX4^rZ)JvXS'
    b'?)4Ulx51X!sQPC+8`ReR%v@7mXEv+)8HRLck(5<-$tt@tk-tpwvI?vi_i4;&U7y)rck3~C!SM_3HzIgbz2aC;^qXC0l$RQdmm(V?'
    b'65D}Xdrz`hFR|ND&T<C{^#i38?L+N=FC&2Jh0x23ob9eU?ksB7-v8zOY_l?gz#bqi_C)+5U&VO?y3I#o@)Zb6RSa8-5pFh0KFGsS'
    b'TsuM?cl^L=h4o~drjR$thu!NKK39{utxFp6Tl2gwoVaM0W<`j*uiQf_G_&P3s4-uH-ynQy0FaMNO&1s-n(w|qzH+WsRW4RYv7KVq'
    b'96)K0P%3jG%~js{tgXUVXWGgdb)_4u_3zh(-o=AA`mG47ec8hU%7*ZJKI|lx<Ur=U$jh(jBGBEs){cGat8>vh9~7(MrLfhoraeG;'
    b'N(Td))D6vw4jt9H>=6X_pWkr%zBg5Dt_gYaeMcP$^snS^)L!DvW?8opvy)k%uCGQW4w~g+`WwuTZ&?t9uoyU&{DDuqI?;p8OQNNC'
    b'fMAy8D{%w*2?)j|UK#<L>E>Xs=?J9~;jG)qKV~2PSmK2S_}>-dd1o~N*E*P4z%>sv3t#S*b^-kPVW$_@FG9xmb!)pe8=!{s^F<<e'
    b'ih*u(oBc`G*Eca&Fca;6LfCu8@Zut@@slryHyP)J$ZD&QT4yYD3US$%I;`sfm4dGo1h>Mf46KM?hE>^B+OBW?o3tr?i}78hMyaWb'
    b'Ch>Fjdv0$fUsL)jtz=3)q(uG&E*ch8Ww~Oir3wH$nibsHBEtfYc6tgmMy*^cPm8T`JDl*5rB*r7b3omS9l`m7H)K4hH}*DSXf9+N'
    b'+SS8cC1Zq30$ghhTL|$~<kx~Xh4U$g9jY{nLR735KWGv{sebacfe*PFqAn;#Hq0{Ee7>UGrbt$y#+_ob6<8#gvMJ#lY+miOaAv%='
    b'=xLgj-L$xw!@Xm{Qwf32Yojeonx-#{vs*s=CO|~xQR!Vrw{?YOt7S;}0NnEE;CEdxeVS{f7U7GR8;X8@D-<vlMM~3(plKyiQEfE+'
    b'A={yYLfKGJ7_?H+xmg%;8a(9x=_%ans+;dN{+Hx`dEiz&^hIk77k&pbr^1XI9G9=1GY{{tW-{@2kM0D6bloA;Uu5+Sij3knv?8~S'
    b'Wnp;5gtR)07tMnIue`7AZsSJM{qA4UC-b4j5he5eMZUae99v0z#&6elb|*)p<!Q2;64w-|VN<caS^xKoDiqKF8bG5-I?3HTCzDWQ'
    b'H(m>cLZP0ga*VzccX#ThA@_?KUd|_Fx)-h~&%Pz=i&4e@B=VO(198jYA(otYLy&&Jk_6mGw1M;on0kQZ4@EmakDf1+oAoA#`vu9f'
    b'#JBcbDU%H;GIen7Ei#anS<cBo&~3tgqr^tczGgo~Y+Fk>lLrF(bvlm_hMEE~0nRi`oj?i8taO7lsVu7VuOMwiP;lM>v=lmH-(R9j'
    b'U}gY%&eSq7#lT1Fj14#p{w#~`SiRdN6O{jA-|aRL-YqI+?tt7y(z+;IE>9v13OS=Ko)yYeA?<{@O31<k4bCl71EXGGAIJ~={KeBB'
    b'U%z<|AJHWH{^gtR9VC%Q8#>xy$}}EWjBvkfKE{pxIb~||!i3naVn@Ro(9CSqUM76X+#nQdbOwJ(u^7MtVMasEsOLl1-O(gKT$lQo'
    b'T>czWPAwHjI0N}a)3cAM^+=x-epyyZUsvm1R9<VkSVkT5XHFaE@h_(BNeJ=I9;{CxZX>X_9@|1E>Q5!_gqTT5f%8@%GT)-V`}^%O'
    b'y~(^xp5GE5nk{c`cl_>yE<<M6ps66z$@!%R&q7F8(NJut#1jd4D6?`G!+vi(0GRWl-%bYo47gc3vq3UQTk}pg8;yo(7KdY%2q8KE'
    b'<ZaeV+P%?W*3HJlEbT1X*?8Pf=Kb~<&{?C|ywi%UxXhFI|2zQY^5V<+XRyE6{`Q}b?>Q^Z`TguOd<0>Am+^tfAHUqpVONE79(x6h'
    b'we^iFDEk=1BehG0%&sf64i#<%>XN_AN?x31Jx&>KHC%^P@IW-{Q%8gg(A%f)E?<A(;Hx0CXaU9%iqFs4M(e7$><_9XB&;B$vf@73'
    b'<K?vvi5@KAY3py*gQ0kk^^B%pU1&D%#u`#G8|TjWuvXV>sx&m!qAz&lk4Su4cX(vsxKHm>wyVH0Vwo^@Nd87HW#ON>x<^t$Yy|rZ'
    b'(4G*Tc^wu*MgqrgI(|_wyxm?HhF4{vLjbRi*|qOS9yqH4)wS(6v9Zi9R1B`8GhahF9?d0O#bT`nmcfN%>^!`_SnI@$HffIjJ5u2E'
    b'I;2(qO+&4g(5K?kW5b5=ArqZqe}borf;RH$9oTLZx?WlXd)$WbYWDY$C~^9GbKhE_tVO|Si0*v5P~$j~LMd$VnSDq(>vCLP{J#hm'
    b'JpeRWOsSR_cW=zBtGuQ)gZBPo6IPEoU^VwGn<y3!A1sdbC96DcK|#$`NnfmC&H72I2yW(yW2fYCno7taKuwuRn5-d{3#pf*AxzcF'
    b'LKR;sz>DmYiW$`*qYjX%f+N*nq#^=X#-|+{PU_Np|FiI<M}m_6;ULo7f+Dp}ffqLV{|#!?hc*00m{HwwsS$YZ47PXf2&HiQkn=-B'
    b'Io$}SrFr1dWBrd%XGN;YlGjj0chW`IjB{J(4lkm^q||4{5?4fOFAO$ArSXer@>|upM6PX1*GU24H(fm-(ZZEq6C)~K+!rEB2vJ^2'
    b'+-UB%7Ap@E4$PpXCyg4`zV#J}rf`5MSdpiMq)_aMdN2t<NdQPfgFryR$HqTAaRDCo!aE!v?x5@d-wf<vHqU3_h6!S$IkMx-QK{&5'
    b't|h)vMBYr7Ilpf(^^Yxj(I32M1mK)*^%F}uyib|-Q@F}J-Re%iKm~Pu)S$>BCejxYd0ICh(rCPKFU37PO^ZXz9JLY!=l-#gBU>Eg'
    b'QNkd#gAJWO;4wIUh~P(#g7{WpkB3A(9vJjk#3W9P1;LEpzxG-r>h&TWl|sE?j=%A7HsTvy;f;huu?9Bo8Q16uYYf)2zL>^<9Ob&8'
    b'pI$j<!I5^{;WH2!85IaxE-+}@Y?aKi6?#yUT;cVD|JXFEZP5^f4Dlm^iX;p==7o$+T!66vpx9($#T-p0R=2$ubTlbwE-sFPIASFd'
    b'-bh2poN};Hz?s}o*nb2_#}g)@Lv-Q<r1q=!hHK+;fO7(lOSDU!?KWo^|0ff6hT(H)8}kBmocJ88NP&5(;94vjBs`(sF`4CQXd2^D'
    b't<XxWjDVO-d_Wl;Co>5_$!O>pziJD@!bm8LiiDvMmmeS=6ysdxWJm*q(HZ0NH-4bJ%XYV$RBFXr_6jq0Phj{k+P29Rof&y6))hR*'
    b'6fZsx5vI0TgjGw&TJ|J;DxP(Kw&1Pgfi-R$LCd561)caCvuA-|6>M@CsQ(?cqf^-6{<;3=`u&&n?lyw}O)e)9>stabZgHXYxoyn#'
    b'cGIC_4e;q?!tB#zcLv@KrozuMxB;f_$Cj7id5k&M-nw_J0$CPHhZue(0vUm+MoM0)N!iUv{~p}05)8H&R1uU)@q`Ui7O(?ieD#gU'
    b'*mU_b6br?Rn_{TzbdfRT2hmS(G=gO1Y#(O3B@kpoe9K~a^T64H&5bwI@K^Px+F(qP3vLaM66PQiX4t~B^oP~al&$jz<&ejvku<0Y'
    b'<G@lx(p$v5W8&MB3acNQdJd0HA+CK2rgZZPn+{)|*d#D>NZ@JwAHVS?eq|?SYGrf(vIv45Sdw#Hi1$l2o4Cj!!FhliZKj;2pKh1C'
    b'3<d(yE<m<!;K1Lkfnpkb2|&A#c^T#yGi3_Ua($bDw<n#*&H2NdzhAy)+jF`(V-s`6_PI~V7VdC<{K@^>`%Bi350+nS=1Kh1hYxSx'
    b'Pv5?K^N(NHE4RDdeSY!yvHq&ibx`q(58$N!;l+>aKR>^QYTESm)AxUW`}F<$(2C!`|7rU4=MO(k-@keGcUwPxdh_bi+IJg{r1ad^'
    b'!xtt^b0c6uYA;`%w3@S+oe%InW0OOa+!xlayJQD$9Hu+|xyD}sm%`m_@IuT4O<C7I>rIME<ABv)TG2uk;G&*0`Q0@;$|V6Rzb5L('
    b'iT0>m|L&ss%jbxrDHb7q2}|&71!0x=X}O-S9?~qwKY%Ij41g;9A>fk`tFqZ{HF<oz(n7xbVH2^gtJbx<P0C~Ki|eMaF9)S^ExqA;'
    b'*x8W1cNJqnyuF*VU2>C)&pdz`e?EhK6~9ljdv=Izi)WZ!^{~yeGiI+bqy1rpJr~Q6XJ<HP^*vrKXPYnV$lB|i&F>!`GpSwQd|9r~'
    b'mKzT1YK8~d8n^q>W=8uJ&AVj9?10sMww>TKZDD)(_?8X9gc^5_XQQ9cR*>H<HUJ%YmvK~MK3RZ6kNtSR-Rw5=&FUPXB@^6d)vvL)'
    b'^kcI6lzf5f6Fqzh+t`#whk`AG^>7E~A)n5VpKwBB_Dg*256w|tZm{zZgy67Ny<|r)p?tWm`EdE})r;56He^cj)!Prc5`6vU{V(r7'
    b'T)xu3{qg0S@1MRj^kS2%Jo@XaFEfX!^OUBZ<4|aU5#@zkJbq>E!gVul#dQiWd&>%F?^6H`414`?n*I8C{jgdE7lTt0`X(tHO&ru='
    b')R#cQF-?38z<#iK*kRNJlM|5Chx``*19e`Mri;JbEStn=ENm7Fqy*S4?=n^_7?uxf*#9AhoJ>j#0iVuSo19q;uwTK0%&6Ud@w<1Z'
    b'Z1A=5(hIF>Lg5gLn6tg9&9@rG&p~f+7qGH<728w0(^H-obrIs7m$#Q!;+t>9)NO5F-R}Y~+@cQISKF@P@08&h9Q_A!!_Ov6LVzor'
    b'-@B0eko_oq%<{H4r;Fk&wMmgE*na_|%NuuTND?dJR<aBlogydNkrGez+(Ft<#R&@Kz1JS6W531IqP$E^vAo_WoY>+R&swbb0hk8k'
    b'u3GVH+3yCkfTntdFEsFM>kK?*?~3WL9PCRHxz7>V;!dQI3b@r2jhl!M&HdLijOQUHwcltCaYN$LeGFpvn1n$%wJOL{!*xKY9%!jk'
    b'@6Z5+QO4FYx2>jRC37+vCcV0Af?OF}j2%IxVN(Dfvo8*-FK%kzm5kAIcH-TFZLV2^T%5#L78BO?7&8JtgLVI~U7hFoEqlT6ud)BK'
    b'^K_DK7VIhN_BqdtA^u!0&N-m}0=zWhM`5;t7n9$Au<3*R?&t6n%)Wi6EK5Hds0sW3x8J$6J7Ff?Q1dAUVieI4b)}tRg`#3YfsKZX'
    b'Q4@TiG>B>ZyX}1?ZyfiD@RW1n(rcDYZ!%Un$FNUlU-*?g?1V@=FcoXoE84n8hlzpe76vol>iIo}NU&d<@dEd{0J+)M`4=JqoTY&e'
    b'azt}T`$NRX{3uh8{y>Wt@rlpF_~;QE{U70IGU`rWJimPX;l+m+m+ujp`CddVK3%8J_|BT2t1O=AViVDZs0o>j4f@kGo39eC36Uz('
    b'U67zzpLWJmehraN*^VGVu$+?x91zp?09d<tf*yB)OnFj4qFodbC}Z}7?=b%a5df)Twn0^7+3{KN)+D3KMYtbT3#Alg3jA&{B6!sB'
    b'7hSxrzQ@c-n7V|WUY7rQ$f!PlN$bsew%M$*gef)d`NH;bx4S@#`il_Vqn<#(BbFh?@#cY@kfovPFAI4Rl<twn!GT|{(m9mGV`Vqn'
    b'Jg`jIW+3boqK!nf)0B9A@E8YtC)4}^!uS?UKxfJPV?`@5&<f*J#iX)cPnS%1HlNm11Fz9vkVxuDDSmUJo%<CdIoB!l7P_t^0}Na('
    b'Hwh#bq4?Qp&Xm|)mQ&yt5`>7bQ(R0BYmr_9k<|RgoRxgfEaP_=$9AqKE>t<*u~axOuaE~`vK-{BOHBRGjrCel1xByUGbm%FfTEc~'
    b'nP(VqL7^4-!#&(;E5b?<c$MWNFMt`RE5masstl%hjRI1H@ZJNl%UyCqRlr3*4f|)fKgAn^95o!<;FuII*a%a9l03^xZ=qb`{rr3j'
    b'EQzeQ0P5$;7?WLQUpAmVA#&mVj@RO-n*i$hH2=7~7gO?a4bsSw1!B|Yww6%_oD!H-^Lft07id70wI>v2W~pDiB$m6XAg8lLm;s9='
    b'TYg%*Kq!+^dGsQ)Hl<>|d&v2w1WDhwV7~D>W^8j=m1pC>vh8NNxq};RkPSA%ibCNey*Nyu+l9*qqq39rJX=ZatCe}XOd;_clb&pc'
    b'ypVj1`QYadYz;DnkS_D&hFPuPy|Nc0o<uV%7rSK2#Fh5P^=2y6F@FY&U>{gJzlY5<*)B6t7#o{a26v!4+^na|``gW0mctGmn>!2#'
    b'$6O{<i>ExuAHB`~^{@mvy4~O%*<CUxX@Gl@>5NJ1oNISjAUjWKM6?Co5pr~}p2CY_$oUBf<T3O05?9IWfhm6|Wdk9r6je$z8FIPs'
    b'gcO{pA>VE8D@&ax_ZU|HG0WJR$#-lKY^N*GzEIR^d4~!eOba%2De~00OXPb3u$rtN?x&v;-fMBki0Xs~ynbA+R{n8A{Y>jX0z-tx'
    b'qZZ}Kf+-L70!-9&xA~Z@^MFz%ogvdx%LHZx&NHYTHfs(Ifr6PRcnVAIX6zuldB{bvIjLb-YSeBi{`Mk3|E{qeDcet=1kpl>l$O(('
    b'<!p{X1wizocP(Iyo0MMK;~}pW#QETgpolv08)`+b<P}N-$TFCee9<iq$7=<KkdxoS!hvbSI6)d$J%H$3VSUNjnH^UmG#>qjy59i0'
    b'!VGAxb8}~5yi$lpr%)kUfZ1pGo(UwvaIj7P`GC(8r+%SyY{ha-0?kWyKx48inpp@cJA^29jWS-g66HnxmXx~QT_6`>Tk?{P$MWuB'
    b'g(n>L&&_tj7MWT&MKe9)=D`QnA~cSmH`@9XrzAJ?Zz(c9sCaz<(d5Aa$K=%+SxG!kDMotnN6hjSRD*8M_4*_q0=_i8U$OP4W{K{!'
    b'iXxeU81y~mqT6Y+n6l{vX%Yu3Fk)c`(GC@Bv};K^(P*qHc%6L`7DEYPOCH}la*6Xf4=>g@?$F^}><AJu0an_SM1Q$idrF2vjdNh('
    b'-bl9_v=S8Ut)!aul#1I+uU9Cf*#<p;WIn6YR_tFn6UO8&_lX1B1bclm0S0U6!~M-RNx2h-321UhOA2D3K}&IN;=nn>%^KScCl4Vb'
    b'RH?7iH2Up6KjKO*#A%O7)~}hg(~HilTG&x4dZmn2Tck~dih#Kli7`?BmEzed!2LI%%|Z<oI=_H`YlywgC$R|xih{0pkj_gi3JnIR'
    b'_02aP;Nl?lT?jydGu%=_6zzz{z7-juT;(z)2sV1Ez>dTbiDcMz`U@CZ$+%wZ&LD8IzJhWcPfqO2B)HdePQJdYl3i0ggkWIFoaj}a'
    b'uX&6YU(2A80w&N_1yY0Ixdg8UAm~4lsXN8}^pxK$1x)1>F3Z(%<<<{6LvZ3OqMfao&YP3-;}&Bxo>9dmYgb!0GJ06}KLoO2_CV)v'
    b'v_Eu<il00y>XAgsf<c*%v?X_e$*wP(qGK(vN{m3}NBHl#hF0yRd%@YqEj^hph&EiNFo_wDM1a{T_ppIv-m;~r7f23H0F8@+E#2Kl'
    b'(_?`9kPFvYYVBm^{{HWqRn}YTaq|9ot2i{nlYdkWN%G(=`B0W{DBQ|0d44GAV@1iwAbhH*;s~@VRl{=>kbPAphX829hG=gT85D0v'
    b'Z=4@3V7{u3<3v?g)pA%kR#oXoiPovA<QM?~l@or@oow7t@Add?AyJwDO-njUhQ0B;)gE;E?eTEY>8HK%sN3rdTcfm>wYrP(e7MNk'
    b't$A<MYY%3<)_6Qiliq01O*`{ZFMh=S2iM2q1j{NB$E?+c?Nmqr#qTt~`|i7U88F^Qxc-V{<FJoKi|ytv0`C1SbU%-Fx9seHa~r`x'
    b'MPi?h_|fH@6@^72(r6MT`R*LamQR%Qrt!mWaW)e94-jn#gcj@p1%3!FL13m)(hV#?uz}_A>m$kFy~^Pd8(H#aoAiqYqXC}xWscri'
    b'$REU>ZDNC-0TAnXwrE_GGigGhYl`J!FBpZ|3tnT^%@Zj4hle$~U|8wAuBZ8z^<4S3VXG92Ez&?iy)yqdB+Y;d@Efxs@+EB1I<j6A'
    b'yDC&(XRqSm+A{1t7pt%k3qIFMM35d1x7_ByLBfu}Cs){Xn9=p-8d8L$^al<!qTKNbDP9;Oe{JI8S<|jWZ9q^liwP%+vU0_1Jd4^F'
    b'Ya%q7Qk4x;<{nYk0gsR6Hh{Ww)P*Py2zV~OgTJifsp9KOqxDL}mdRCDED_?rF@}u-&9GuxvIOZYtz2cvinZWf-J-J;rvQ8OYB@XS'
    b'^dAOo6YqEtLvwzceNLA*5XgbU;nG#U!FWa_0&)bDQ6U);oIq&0TL*;0CSND8i9PEi3p(<A*_##|+@?&}wy@OTGg#!T4Epl9@Xw#H'
    b'{hSpuiMf8y(z7+Tq1`(x1y!f%Gk)!GA`3sKi-?BFC-jz?mdazWtPNryxW{D`DR~KAKmG9H-!3@=rU^%fy%aYvg%pTNa6NfWR5*7Z'
    b'+0IBYq+HQ9d7#~NW2SjAOHes?sFC2;Mgw8d>Pdm6mN51B?B{n#<H@B*X{EtsSVAm9r;2DO^#3rcmSZR*>GUq6UPGi_zJ3++*`@30'
    b'7}@2-!LG~~t*#C;mc3Y!@(`<qyBIhACE6*TMM4bMhc|CtzK0w_3ct6I$SH3#a(dg@o;*Ax4)xM#GHqz~X`Ov)_u$;q?hE_5+Y_JK'
    b'V}8=7;?Ps69rQyf@kz>+ATvmi$CmuKmGrZAI~k6~^JJ9H$Kz}^N|Pk(%-h+B8AHQXD}dEpEuX0IXR~gv-R^Wd-9geBwK~IDHlO$V'
    b'S!=N9_UE(CxHp>(+oOe@8vnN#5~{xCF%p;TB>N)IAF|iUuge?0N;u`gF*)J=)bno2d)UBl;MlX>BzNG9U~{)kcKb5ue>-me8+N>d'
    b'<6@R<!RsfR&9-r{O)I(inTbDR2R9~}cW~ui+_q}1+AB>+09n7d#)ml)r^oqn3ehxQ%=7@ZW$dp)f4;czBe}6OCA^BTBoCSpN^dVW'
    b'JoE$#U;V%`%f=SQ{jbn;885ecHDCMX<(sF^i`UzYI!!kDNPt)U70+>}P{oT5ef5-mrL?VFY5)_wCqu3Bwuegv80*`8V3cRWFutzV'
    b'q$Gf<yS(7flpDPyzp!Qu=KEYgfwZZWi>+*?x%IQ{P2ISCB=_@ff6(c4dP#TKNqfCcuiMMg&S*9t4cbYz=nh-+MSGO79|z+F+o5LT'
    b';jER627UI<aJJ|NY)9zGTBbzA9Je~KpS7}1YurhCtxkWK%@?C=oUkpgyXX&xgC0Bj_q!UU19|gAjzZ$mO;3=tt2AOFmzZi~1@d@C'
    b'v7C<xtsuD3v?Hqn=2AA?m*m52{Z))X2gu}a`LcSz<+Y2cKg)GBBi&qWC||g;8^i4xD-mw0?{B~4=)08>i{QE9q=F)_SKMzf`^L#Y'
    b'TFPr^8(Vs}x(^lVjVjYQ_^ry)eqISoI9RGYbhSp7byJm|+vvr+%NMVnGL3g7+I(GKiBRXRYT0zx!HOsCF0wRP%*WXx8@Gp@PHWMd'
    b'_dD}hZ$9dz!(L}G>a~(#w>9kd25HjmXT3COcbV>KrNc!!i)*X{XW|E4aGH@KZ<9h!Ds$#kS45Ioqs<1rXZ|gl?W;?++&C$1roZ;3'
    b'n_fiPs+TRoYFZ^<csM){thNJCtr@OW0`jJ$Ts&hZ<5K=>Qnc`q+H%IBUk>tmV7@DEJJ2gHb0`YldPvDE0!u=9>phz{nkg_ADwn-+'
    b'7!RPZPqS6n>pn7fY{!)tst_u7b@1i;CC@=EZhdDVR=$1L(}5iPzWPE~`8BC>mvtyzzap2i5|wN2y4WHW_kpKCMYQz-@vDL;zt;*$'
    b'B0vRTXhx=Y8`B9;ZuRo9MI~P;=>DlVC4Nhx@r7djhe&7ZIf;LWU#v{xuX((VK<FREG!7nO|L7>p{v~TqP|26<BQq&EU23DtQA9%U'
    b'KoK?c#EkP2m*Z?;?=zcHM{UEkx}LZO98wBjb2HNUx|<qfv!;<{Y?)A9$I;8cQSa8u_H}ORYV56^WCA+Vz^oR;(kKOX&?_%DvjECK'
    b'YJ1(bTKQ<3IX{#)ZOJ~0my}!`#XDEO(L}KyVmUAH2WK0Pzh2w3coapH_LT}+%7B$bNyqfmgfXoj={FZkd+&wiIfDeQEFRFOdyh=)'
    b'Cr3vBu!gP~(8-L!`7n<XrLadbAmOQoTj$^IFN%!Kx)Z(d;&{$NU;RfRS(W`PWaM(NUE4UVK*{4B#p~=7r?_F?0vi|%5NZV(L}WuR'
    b'V;B>AQlyK3&nIPy2K?<|4RxJZ$%>2ZP;gvRdHm1mZsWQ8dE_Vb7CpNtXL^7Uw&ts_?9*~k?9>&dviZNSSQW5?|3}omhAcbqXZylI'
    b'iM+|rA0S@lgeQ1k=aUmLz~|r`fZwL;ycwzA-qE*>svamaX&Z_oI0tM;;;Ix5QrguWzpPX=Khh7&RrY$b`vGooxuWs&iPY<qlTjPT'
    b'j2*T}DB0?U#SLHLg(s}c3Q4yKpyG-<ytOjTo7GHglw0OtVy`#c2Q=I``O0gr>3q9duzyjAof#S^0KPnctUzS&!$yrHJo2J^;uy0h'
    b'RSH%lhH)j!LFFqGz?`V*T~P5fLH}%#X(w|0NI#*fdi*#N8D#!hGSN!%WlN|MZpS@2+<3EOopc@_sIlrP;Ym5iWbwLi;@LXsCnNnc'
    b'nme}juv|;ohCoNO3$;@2l6!fqSY+%+CFYk0lmA}+V85pcJ_vRK=dpsWAIQfR;IC2hgE%x^mD{E$<;vkv;IU$#V~a5^->ke>zm85P'
    b'+|H<R?mb#Ix<L1)Ox0m3Wm@zC2`i99;%*vlAGjxyPM%sA2Y~<_!pO<))yPE;FMrjpr4Enl2yZ3Zm-Sn(XpGjLKiorsCsd%~LYjDj'
    b'P}HZ9pwAUh;&LsUE(oK5*H2$vmQ0BwcHVG0lsk`y2&0qAce35)`lr3Ilyi)?j_m;a0p+lbez&;R!S^`sA8q(}v+9XXanpE(ylL=X'
    b'4x}mhcYj|IFIGH+&r{MJ3Xg-0sY&UpG^^^9C0`gEam*~o-kf0&piHjKBAc5vMHMAGwA|@dn<dv;v(J&FE<GtV9gbU$TwTK0I5F%%'
    b'XXK&!zoL)A+|*C{8@{ac75)6h(;r{IdH><XGp-%JfBEM7_wxF^9O3vWw_GLz6cY&(2(KkEFu6e6swfx;Dg+{;1cO%ta>+$DE>k8v'
    b'5HTf8ZcU`j{l}L0tjcziB!H14xf?a0f#Yt?@aD};%|jbWs4&M{r5%L66ygSrWv`5YBAK6Uoo1hLzCk*%YSH5G>}-^%4DRkQCtDQn'
    b'zHn4saS!A;6-$ka5gwxI@U(1H08h&XeF;yiCX_k8hNgT58v7)^YMqUfv&Hpqz1COg1i50H`U}knk?@mtNR2#)TB%0uZ!-ZKRLzsF'
    b'u}?v@;HU@JLaK(<A~M(b>H!;*#+vT!v|{(m?Z(A#g8$aNE{7~RI)jN7S9`~`C!{*U8Z308EKH<O<J+5{9FF`sbYQZtVs<t-!-&qf'
    b'899wT7zCLd<-!OhH|;%teFd{|1PN3OYGZzHho+NA>Smsr#3M{n6TYM_jEqju+8O@|XHOD0mu?%4E<z$EqEd+nMjN}UcNS%7k7KA@'
    b'&9k&iLO3HhorE{f)-DCU#{tEN-Ye&C(sJ(c8+pjOS3-UjlNC5FW=1<l^r)vHtDLT>O9R06icIF&=wDnn%5AbBMznl;LIspJdu};a'
    b'_7_u!3Dr@1wBT(^>%7)!r2*>5uC2u&xpLQ5TABDk){5@M1$mO2{KtK5LFe3Hx?6LEMK&)-W=X3@iWr25R)Sx*ap0}Ozd}%3WWRuG'
    b'I>jl4eu8=_z0}>OMEh(ib$uH%^Z7)2I!37zzZyG|;*PLxNIX%Zx&2gJgqLhiQOlL>G=1&aV1moF7icX>H#3X)EuMNn2@xxPg3@JV'
    b'7Xo|q=XSS6q?tEjtcXDXZLQRRe~KFJx693z*CFvk${+194=dZ2>E-SDRwHl1RdISLSq;YW@TMo|*|+hg6uj$;O0!#rENRI}ixly0'
    b'my>V0okl)Rx2rPTTcP>dHXJWh^TB$T>Nraj@mOWx=g;fp*JQZ@G+;!JRgCujMjB?uEsiQuu8Td`78(*h-Og47%)h!MDulo``$i_#'
    b'u<G>AS4$ir;b@R5(h<8%qdiO{U!o5+?vH5=w>edr71%Gp7_)d_E@ZQGMQ0kbz}Hy4%*dq}3mL;?U*rHmYVwFf=i!u<hj$gKdDozX'
    b'z=fi=W$$IXi>kgI34@ELP_O$F$QFkzOE#CX>{0*qMb9^mqM+zighNdDbJzIpnK8P)wR5nAv$qp`Kg-9AgVbr4@R%UDmms8qV7^lz'
    b'3YkLxGUACc&g+5K`aDlbacdt_U6{hpmex*OKdM6s`P81jcsI#++Y?@3gMazr_4CVrOn-Rs@)CbD>p<5^Y#>}@stjvdO*ZYA!tUjV'
    b'%XduAU7An4xO@-cifVp3@V-IviwN^I7vP778Id-hvk4SAAftFmwBu)Ikk|)5{R>2_=o>Q-S@{#C4z{>K77ZA`>@N;xgW?T#OlO_M'
    b'lphAo0;OoKwUqrE1cUu{@>k4M8A0l1Gw-x|LMi&hi2!-JG1)mR<r+L&?Ar+xR_cl*@o1d0b}iML7HCHdPJC%;o}D3SUwi<k!e$9K'
    b'+E_G1Ih;|RC@B0BuOeq71GW_Qz2a6uD;f*scaUdX)UdoHP5B4J8ZXz24LLKpTaz`YX$hGlnH6p2nKW@6if8^3ePFtntq-;gbF|0s'
    b'6xi-Xd^JbxM<9<$BIJ0Bb{n|w0;Z!Z+TCUmWM)7=j8Y;b1B6s2t7x5lihjC$`usd9oHp<V4Vi2qt0akpo`@hd!nyMRSz5}vP_MFN'
    b'%Z0iER#y8~fO|Zs$>MgzxCW>#OC<rN@`J>}lm_nFu6L=`bi`W9iv+jq1cd%oY-p~jJI;RQpGa}X%jZ!N$yhytPA-|hajy~Q?~vP~'
    b'maGp{Uz1KbrXDPLNAVR{K&o|xKD3g9lz3U-;ds6n&brxf(OL}Wop!4~>vZS6?s(DZwtMNIJ?M@`gL%6%h#TS@S7f{EcE`xJlYp{{'
    b'i@jasfZxNDuAPyx*lNNRFY<S2D{~#Mv~!h~tG?{4<>$?(C_Kx}nx8q#nMKLWKT-!h`2-)7(=Lv7DY2m1A2IG;SDnr!2!-lQf=Bei'
    b'QB{7s)|OYxmsVSNS$QffSKJw=Q}JZJvSyUW(IDnS$ipDbPo&o)Qa(X~XwB>=Q-dRii=Ib5ij}OwoM*6{&pm>K?nYkt(u)p<8Bf{n'
    b'sHU8=-SVK372bT}>oKH4rsNBe3jKY^Lm8QgC?o!*nTpc8dxT|h4->VJq<c|0lY4~n!^Gr}WbRR6$%}OEQIXF*(h|BydPeuCNa<d>'
    b'F>SLEt;)h~<Zq8kr@ukHLR!~6p?f4Vx<_hC_sEsgJyMgpNA9fdel)+alJ>~}AH|?PviYdr8V-_S(#tx%K{oDX<58L}M(xF5Htc3;'
    b')>)V-;1{dp#+?B^GE=}uwjA)0Hwk>?$O0c#q=9$Y!7tV)&}b53F@X)o5&E#)@R3LkA5nIAQgo!(O8Ma<dxH4LmLWdUQ^ZFBIpRGD'
    b'&LeAv^KyQ9Q|%s-U!KykM|)&+x2L9$_RCE#Q_Jfu(f3)hHaI)6OlyXO&IPHiPMy2W7HmVV&dTmfryE()<VIQo+z2z^Vg?*F<E@>~'
    b'N>76umGj_!mOtrPaHFH7!To)<T{9VO1Pu@l8%I9e=%C#0;f7t%j@#CCETy7H8M!)Xlf}Sx8@owS{XnNDtd5I4!xWEc8BzECywd?b'
    b'6VXVkTF@!1EwtTu2dO0=rSltVk_t4unqHU<qC6bO^=1!CY|5+6u*HazLVwgg3jJ=gNDZ{+5cVFW)Df4t)cv8r@F-0lKB=9?(e)uO'
    b'4V(H=otz<#>mjd=ryu!iUtY5(Y>~4_91DJ)s`!C$kAUyCP7JW`YAb+3+Vmn=yz4YlcEoON{RTtyElzxUMU>WABEq@%mMDmyOXidy'
    b'wrD-$Oo<m)=9>aC_-R2^4vj&bS4v%#5Ci!%<GJF#DaWs%0{7DTDz@Sc8T@Ow^+D4CmpcC>nBb*}3-TN*(-*@d_+w#UJkp)Y7`&&#'
    b'VX4lhs9eFxswIQC6o3B%FR=0dkF4v)QvNJPr>&f8NHTl!9a2SP>30n#mvFZwo~~1Jx#fiLjs7B_g!o1M7Sl_<S_RKR&BljAl&>9#'
    b'XPQr!)$4|xgL5?bECA<j(G>7sTc9G+h!@FMixl>lq6{<iaO9#F`Qjp!lWgU764SSD-hFub{mV;@#dHq}Qdy49YR&q#XwQ?`Fk6f}'
    b'$zsm_NoQ%+Yq!%h8@6Y?WYFr5Iw7pqdJPoKGwk;V<FuCz(ovT7=bdhrjYorid(cZpX{$Z&WZmAN-5&VL=kdj6ErKrhWFI2q-;2$-'
    b'J~4Bn4jP)1he4>B86?S>%J_8={KbxAXPjp(kdVnDcQwJ(v6SqBKP-=HfvIco-zh_(6ku(_wUe@~93584*hleIl{J<q*#sH~BBg-6'
    b'{pYpdXr?fsMg<KWO|DY6#DxOM9c6Om+;6AAbw|*7HwN9#-Ye$R!rA++;O7-O(Sb29vPN>4qMD(R`;9R7DxMM{?GoDsc1y~F0P!62'
    b'a&(Y^jg{^4>1Q{+0S;A2rVmli+3uD#_6#XpH>)##)RR>5#$|+()k8i~#tmA626UBLo)n1?GA{U^&@X#t@hFPc*hYf$b9~#bam$$6'
    b'r`G!<%6G}#eet7%uFBFiKbzB&g1U*n%gLLtHl4Xie&wNU+6Vd_DBkv%b?UE^w&;&)(0=S+fAsJ@vB{5iehNlXBSgE{;|eqF@`pF?'
    b'2nA%~)qlIcFr$0)!Fz0Q)Rjr<^riRpQ4p}oKsE6~n*z>+JrVoRbq!Bk;bw3kPZ8R5x<AfaPQ4xq#P2p$M5zX&Z8VxTWOsq;?uA3S'
    b'3BgT(?rQw@EJ-K0y<^vX5&e@%Vc@a1IAXg3)eP?-a+<wxwY;A2|CE8!BABeYI1c@$;w0cZIa{>O#sv6|Tk&6ettNk_Spo89W)F0R'
    b'j4=L=2MfKwXtAP6vYJPMGw&&C=E)Y$8&fUMZ;@BFIQDYlG>*^%zCdA8F>_4NsFmq>BpF(*gOAH6Rbd7^(kWt1<wGgr-o5#Eg=@by'
    b')qY4`G0XxGO0M4;4F`j9YcL#-lWvQhkh7%Ip7jUabkG`h7K_EGo%MU&*{t15)A?ZB9VO#gKWp{6{m!^M7{=c;=SU~ZdW%+?%m>|8'
    b'HW&}nb}MZS`s04mPUfBdFzvU}-gq(27QIe8TZ|X2dAr{mXZ-~`*e_b6*hgF^d`P+%2w}6F;+7v@IFaqObnO)$sz*)-_9ubA^%c|z'
    b'aw6F_djI^J1adM-CAY~Hp?y@k4S++WJ!(Bz^aQsg91opKhi~qpWxU#|Ag#BED2|Kf<8^ORlMv}hC#gqeB<5iR3?A>;slvaY&qmqP'
    b'6&l59;a|{@YHXuRU=zF019ng28GL)H+&Z0lTdvY7h@o~87^u~IN;TW$91L4C%bt}}gJXe7cDaQb?urc#BK{C_RkzV5U{5~$^64*^'
    b'?=1eAhO-ehh!Dzca~wp`w4GF$=z*Pf+VHSA4zt{?!~nV(e>yt_`~6f}?<Lcn+e0-*PlYwqntdy$!o)atoNje82j2XxPUCO{*05?`'
    b'hf|*bT-{%50~<*25K8QDYNK_qWV>y+(d<?>-s}@MBk#pZZ}+C{{<O>fJtlNsk+Gce-ml6@XhN;<QkaZ_dGy5i>WD|Kgk6LV6Nf=='
    b'g*8_B(LKZqbkoEPxcIusn^gB*o<yX{w~yeLWsh{~2hTz~jHDufqr%QCA&4d58jEmE26cpXDIz%{VnrC?u<YV{5Sei`0WT{Re&o}o'
    b'%~%u_kpIcVv=V5-{n&oC83|B7Em&-diL$re{RI+(SeyZz-N9NRg~zA{K)ev9i<Q*DFqmK<YMW;ggw0wfCE=oAUHEGS=Yq5>0=NWf'
    b'?l(?f3SAtP%o9GI^&$VPWc5Nyot;w-_P1U#1r#fg{`Lt+oIi*8yHWm@;j@rwD6^=p&x=4<e$iC5B!c8Ci2Sf|P<y+Vr%~OA#D!J;'
    b'9jJK_KC%ARWT3yq`z79HwyhV@mu1FgKU1?9`$-5*^C5)E!F<WJc##8K2F~NIl~z}bhu2sz#=*8n`&3g?e?c7$OW;QNcs_BQn*bxE'
    b'9+tjA&yC<*t98<h%l%WobTUVSAKXD24NhTB7(MaRMIR^zte#pTa9jfDBTkqF+RP6SUTCulWabLP?r1O<t<B9)@-GzNSmbal;Kx?<'
    b'vBS=@*eI&8mK6>nEAAMcN6eRL;&~XI4gnrpamNRA%^4UBLmCJ!F09}Zv>2)X4*(T=&VCY7?0&f}pqO@wiV*p#2>23~7zbeqNMezg'
    b'SpbI#M~r^rV~vZ1j#Q6J(~Pe+!>jQt15SJR0EVDM6qGFB>Lzw*EVB#|arlIz?>tZO2i#4Nz|+pfb@OU3)TevJH!AAwTsH@;#uFV?'
    b'se)Mrs?vPK2lRBkV*{3!P@AQ8YVbxEU=Z+vPs$)i4g22IN-|c=44iAYT7>z@F>zCfg#pkXI-58Mh-Y?MZE|~3V~GMR&j(X}=6+KT'
    b'`~$2?{OIXhWg6%QmUuI0v#zz2xN1()N;nQ5M;wt^Sp?u*KPy2a`L_UvgxhophU8zX(8qF~sozC=nZQKeM;(axZH7EVgSAaUA7tl)'
    b'2{>t^R&6435I+48gIA^cd3&$_B!k&8Vxy9@j23HD5>SdY>wir>SXI1H=@JX}J4zcfz-r@HKx_=YiSHu7hWbW=;ALrf#KvVhg%jy?'
    b'ieb{z>0Pp1Pp9PAlP3`Pmc8(Q0f$&HOa'
)
ORIGINAL108_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity', 'NativeC2afBoundary.test_original83_complete_method_sources_are_unchanged', 'NativeC2afBoundary.test_new14_old15_history34_history19_and_original65_remain_separate', 'NativeC2afBoundary.test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources', 'NativeC2afBoundary.test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted', 'NativeC2afBoundary.test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape', 'NativeC2afBoundary.test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation', 'NativeC2afBoundary.test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse', 'NativeC2afBoundary.test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks', 'NativeC2afBoundary.test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks', 'NativeC2afBoundary.test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory', 'NativeC2afBoundary.test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer', 'NativeC2afBoundary.test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport', 'FixedPublicRepairRead.test_present_exact_3393_never_fetches', 'FixedPublicRepairRead.test_missing_3393_uses_only_separate_fixed_public_bounded_fetch', 'FixedPublicRepairRead.test_3393_network_failures_and_credential_configuration_refuse_without_retry', 'FixedPublicRepairRead.test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail', 'PortableDiagnosticBoundary.test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings', 'PortableDiagnosticBoundary.test_exact_f04_selection_source_and_four_path_layer_are_mandatory', 'PortableDiagnosticBoundary.test_all_four_actual_current_files_and_both_tree_authorities_are_strict', 'PortableDiagnosticBoundary.test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk', 'PortableDiagnosticBoundary.test_new4_and_published14_15_34_19_scope_cannot_be_relabelled', 'PortableDiagnosticBoundary.test_portable_receipt_requires_new_identity_before_original65_checks', 'FixedPublicNativeRead.test_present_c2af_never_fetches', 'FixedPublicNativeRead.test_missing_c2af_is_one_exact_bounded_public_read', 'FixedPublicNativeRead.test_bad_c2af_identity_config_timeout_and_parent_fail_closed')
ORIGINAL108_SOURCE_SHA256 = 'ba510b25a5db3c55c7337077547bd4975d219947a250f29a2de5d42d1a09211a'


def description_7b_test_source():
    """Decode only the fixed, independently authenticated complete 7b test file."""
    import base64
    import zlib
    raw = zlib.decompress(base64.b85decode(DESCRIPTION_7B_TEST_PACKED))
    if (runner.hashlib.sha256(raw).hexdigest() != DESCRIPTION_7B_TEST_SHA256
            or runner.blob_id(raw) != DESCRIPTION_7B_TEST_BLOB):
        raise ValueError('Changed complete 7b historical diagnostic source')
    return raw


def original108_source_blocks(raw):
    """Bind every original method byte, including decorators and body comments."""
    tree = ast.parse(raw.decode('utf-8'))
    lines = raw.splitlines(keepends=True)
    found = {}
    for cls in tree.body:
        if not isinstance(cls, ast.ClassDef): continue
        for node in cls.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
            identity = cls.name + '.' + node.name
            if identity not in ORIGINAL108_IDENTITIES: continue
            if identity in found: raise ValueError('Duplicate original108 method identity')
            first = min([node.lineno] + [d.lineno for d in node.decorator_list])
            found[identity] = b''.join(lines[first - 1:node.end_lineno]).decode('utf-8')
    if len(found) != 108 or set(found) != set(ORIGINAL108_IDENTITIES):
        raise ValueError('Missing complete original108 method identity')
    return found


def verify_original108_source(raw):
    found = original108_source_blocks(raw)
    if runner.hashlib.sha256(runner.encode(found).encode()).hexdigest() != ORIGINAL108_SOURCE_SHA256:
        raise ValueError('Changed complete original108 method source bytes')
    return found


def description_test_inputs(selection, current):
    """After checking real current11, build a bounded physical 7b source view.

    Only exact, authenticated predecessor payloads and the fixed complete 7b
    diagnostic source are restored. The runner remains the real loaded current
    implementation. This is no substitute for a checkout or Git scope evidence.
    Every remaining historical input must exist inside the current source root.
    """
    runner.validate_description_selection(selection, current)
    restored = runner.description_predecessor_sources(selection, current)
    old = runner.description_predecessor_selection(selection)
    old_selection = (json.dumps(old, indent=2, ensure_ascii=True) + '\n').encode()
    if runner.blob_id(old_selection) != runner.DESCRIPTION_BEFORE_BLOBS['tools/targeted_native_selection.json']:
        raise ValueError('Exact 7b selection source not restored')
    old_test = description_7b_test_source()
    if runner.blob_id(old_test) != runner.DESCRIPTION_BEFORE_BLOBS['tools/tests/test_targeted_native.py']:
        raise ValueError('Exact 7b diagnostic test authority differs')
    contract = json.loads(restored['tools/run138_editor_readiness_contract.json'])
    paths = set(runner.BOUND_SOURCES) | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS)
    paths.update(runner.STATIC_REPAIR_PATHS)
    paths.update(runner.PATHS)
    paths.update(runner.NATIVE_PATHS)
    paths.update(runner.PORTABLE_PATHS)
    paths.update(runner.DESCRIPTION_PATHS)
    paths.update(contract['feature_batch_sources'])
    paths.update(contract['feature_batch_support_sha256'])
    paths.add('tools/run138_current_source_projection.py')
    temporary = tempfile.TemporaryDirectory(prefix='targeted-7b-inputs-')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name)
    for relative in sorted(paths):
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if relative in restored:
            destination.write_bytes(restored[relative])
        elif relative == 'tools/targeted_native_selection.json':
            destination.write_bytes(old_selection)
        elif relative == 'tools/tests/test_targeted_native.py':
            destination.write_bytes(old_test)
        else:
            source = current / relative
            if (source.is_symlink() or not source.is_file()
                    or not source.resolve(strict=True).is_relative_to(current.resolve(strict=True))):
                raise ValueError('Missing or aliased historical fixture input: ' + relative)
            os.link(source.resolve(strict=True), destination)
    return old, root


DESCRIPTION_TOOLS = TOOLS
DESCRIPTION_SELECTION = runner.read_json(TOOLS / 'targeted_native_selection.json')
DESCRIPTION_SOURCE = Path(os.environ.get('TARGETED_NATIVE_SOURCE_ROOT', str(TOOLS.parent)))
runner.validate_description_selection(DESCRIPTION_SELECTION, DESCRIPTION_SOURCE)
PORTABLE_SELECTION, CURRENT_SOURCE = description_test_inputs(DESCRIPTION_SELECTION, DESCRIPTION_SOURCE)
CURRENT_TOOLS = CURRENT_SOURCE / 'tools'
runner.validate_portable_selection(PORTABLE_SELECTION, CURRENT_SOURCE)
CURRENT_SELECTION = runner.portable_predecessor_selection(PORTABLE_SELECTION)


def c2af_test_inputs(selection, current):
    """Explicit historical fixture for unchanged83; current14 is checked first.

    This bounded view restores only independently authenticated payload bytes.
    It never writes through a hardlink, completes a missing current input, reads
    another ROOT, or changes a historical assertion. Historical diagnostic source
    checks use this runner's real code and the separate, exact v5 selection.
    """
    runner.validate_native_selection(selection, current)
    restored = runner.native_predecessor_sources(selection, current)
    old = runner.native_predecessor_selection(selection)
    contract = json.loads(restored['tools/run138_editor_readiness_contract.json'])
    paths = set(runner.BOUND_SOURCES) | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS)
    paths.update(runner.STATIC_REPAIR_PATHS)
    paths.update(runner.PATHS)
    paths.update(contract['feature_batch_sources'])
    paths.update(contract['feature_batch_support_sha256'])
    paths.add('tools/run138_current_source_projection.py')
    temporary = tempfile.TemporaryDirectory(prefix='targeted-c2af-inputs-')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name)
    for relative in sorted(paths):
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if relative in restored:
            destination.write_bytes(restored[relative])
        elif relative == 'tools/targeted_native_selection.json':
            destination.write_bytes(runner.native_predecessor_selection_bytes(selection))
        else:
            source = current / relative
            if not source.is_file():
                raise ValueError('Missing historical fixture input: ' + relative)
            os.link(source.resolve(strict=True), destination)
    return old, root


SELECTION, SOURCE = c2af_test_inputs(CURRENT_SELECTION, CURRENT_SOURCE)
TOOLS = SOURCE / 'tools'
UUID = '01234567-0123-0123-0123-012345678901'


def static_tree_records(root, before):
    records = []
    for row in SELECTION['static_repair_changes']:
        if not before or row['status'] == 'M':
            records.append('100644 blob ' + row['before_blob' if before else 'after_blob'] + '\t' + row['path'])
    for relative, baseline in runner.STATIC_DIAGNOSTIC_BASE_BLOBS.items():
        raw = (root / relative).read_bytes()
        blob = baseline if before else runner.hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        records.append('100644 blob ' + blob + '\t' + relative)
    return records


def scope_transport(command, root):
    if command[1:3] == ['rev-parse', 'HEAD']: return 'a' * 40
    if command[1:3] == ['rev-parse', 'HEAD^{tree}']: return 'b' * 40
    if command[1:3] == ['rev-parse', runner.BASE_COMMIT + '^{tree}']: return runner.BASE_TREE
    if command[1:3] == ['rev-parse', runner.HISTORICAL_BASE_COMMIT + '^{tree}']: return runner.HISTORICAL_BASE_TREE
    if command[1] == 'rev-list': return 'a' * 40 + ' ' + runner.BASE_COMMIT
    if command[1:3] == ['cat-file', '-e']: return ''
    if command[1:3] == ['cat-file', '-p']:
        return 'tree ' + runner.CREATOR_TREE + '\nparent ' + runner.HISTORICAL_BASE_COMMIT + '\n\nPublished creator witness'
    if command[1] == 'status': return ''
    if command[1] == 'diff':
        changes = (runner.ALLOWED_CHANGES if command[3] == runner.BASE_COMMIT else
                   runner.PARENT_HISTORY_CHANGES if command[3] == runner.CREATOR_COMMIT else
                   runner.HISTORICAL_ALLOWED_CHANGES)
        return '\n'.join(changes)
    if command[1] == 'ls-tree':
        if tuple(command[5:]) == runner.CREATOR_PATHS:
            before = command[3] == runner.HISTORICAL_BASE_TREE
            rows = ['100644 blob ' + r['before_blob' if before else 'after_blob'] + '\t' + r['path']
                    for r in SELECTION['creator_changes'] if not before or r['status'] == 'M']
        elif tuple(command[5:]) == runner.CREATOR_PARENT_PATHS:
            before = command[3] == runner.CREATOR_TREE
            rows = ['100644 blob ' + r['before_blob' if before else 'after_blob'] + '\t' + r['path']
                    for r in SELECTION['creator_parent_changes']]
        else:
            rows = static_tree_records(root, command[3] == runner.BASE_TREE)
        return '\0'.join(rows) + '\0'
    raise AssertionError(command)


def xctests(methods, target):
    return {'testNodes': [{'nodeType': 'Test Plan', 'name': 'Questify', 'children': [
        {'nodeType': 'Unit test bundle', 'name': target, 'children': [
            {'nodeType': 'Test Case', 'name': method.rsplit('/', 1)[-1] + '()',
             'nodeIdentifier': '/'.join(method.split('/')[1:]) + '()', 'result': 'Passed'} for method in methods]}]}]}


def core_transcript(methods, status='passed'):
    lines = []
    for method in methods:
        target, cls, name = method.split('/')
        identity = f"Test Case '-[{target}.{cls} {name}]' "
        lines.extend([identity + 'started.', identity + status + ' (0.001 seconds).'])
    return ('\n'.join(lines) + '\n').encode()


def summary(count):
    return {'totalTestCount': count, 'passedTests': count, 'failedTests': 0, 'skippedTests': 0,
            'expectedFailures': 0, 'devicesAndConfigurations': [{'device': {'deviceId': UUID}}]}


class SelectionAndCommands(unittest.TestCase):
    def test_actual_bound_source_and_all_65_declarations(self):
        self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), SOURCE), SELECTION)
        self.assertEqual([len(g['methods']) for g in SELECTION['groups']], [44, 14, 7])
        self.assertEqual(len(set(m for g in SELECTION['groups'] for m in g['methods'])), 65)

    def test_original_29_methods_are_preserved_and_only_16_added(self):
        legacy = ['QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCurrent401ExpiresOnlyCurrentOwner', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail', 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority', 'QuestifyCoreTests/TemplateAuthoringHTTPTests/testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testNewKeywordNeverDisplaysPreviousQuerySnapshot', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot', 'QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testSameKeywordNewGenerationRejectsOldSuccessAndError', 'QuestifyUITests/TemplateOwnShelfFlowTests/testAccountChangeDismissesReviewAndSignoutClearsShelf', 'QuestifyUITests/TemplateOwnShelfFlowTests/testChineseLargeTextCanCancelReview', 'QuestifyUITests/TemplateOwnShelfFlowTests/testDefaultDisabledHasNoMutationConfirmation', 'QuestifyUITests/TemplateOwnShelfFlowTests/testDeleteRequiresSeparateReviewAndSimulationIsLabelled', 'QuestifyUITests/TemplateOwnShelfFlowTests/testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit', 'QuestifyUITests/TemplateOwnShelfFlowTests/testOwnedDetailBackAndReopenKeepsStableDestination', 'QuestifyUITests/TemplateOwnShelfFlowTests/testUnknownLocksBothActionsAcrossReopen']
        actual = {m for g in SELECTION['groups'] for m in g['methods'] if '/TemplateOwnShelfStateProjectionTests/' not in m}
        self.assertEqual(len(legacy), 29)
        self.assertTrue(set(legacy).issubset(actual))
        self.assertEqual(len(actual - set(legacy)), 16)
        expected = (('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testDuplicateOverLimitHistoricalTagsStayUnchangedOnOpenCancelAndInvalidOwner', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'), ('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testSemicolonTagApplyCancelAndReopenPreserveExactLabels', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCurrent401ExpiresOnlyCurrentOwner', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyCoreTests/MerchantDecorTagDraftTests/testHistoricalLabelsRemainByteExactUntilExplicitRemoval', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'), ('QuestifyCoreTests/MerchantDecorTagDraftTests/testSemicolonCustomLabelRemainsOneLiteralTag', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testAcknowledgedWriteReadbackFailureKeepsLockUntilReadOnlyRetry', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testCancelledReadDoesNotPublishLateServerExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFailedRefreshRetainsSnapshotAndShowsExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFinalPreWriteReadFailureDoesNotDispatchOrReuseConfirmation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testInitialReadFailureShowsExactServerMessageAndRetryClearsItWithoutWriting', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testLateFailureCannotPublishAfterSameAccountTokenReplacement', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testNewReadClearsPriorExplanationBeforeResponse', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testPrepareFailureKeepsSnapshotAndRequiresANewReview', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testSessionResetClearsPreviouslyDisplayedExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnauthorizedCallbackInvalidatesFailureBeforePresentation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnknownWriteReadbackFailureAndMatchingRetryNeverUnlockOrResend', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testWhitespaceAndNonServerErrorsNeverBecomeUserText', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/TemplateAuthoringHTTPTests/testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testNewKeywordNeverDisplaysPreviousQuerySnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testSameKeywordNewGenerationRejectsOldSuccessAndError', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testAccountChangeDismissesReviewAndSignoutClearsShelf', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testChineseLargeTextCanCancelReview', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testDefaultDisabledHasNoMutationConfirmation', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testDeleteRequiresSeparateReviewAndSimulationIsLabelled', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testOwnedDetailBackAndReopenKeepsStableDestination', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testUnknownLocksBothActionsAcrossReopen', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'))
        actual_bindings = sorted((row['method'], row['source']) for g in SELECTION['groups'] for row in g['method_sources'] if '/TemplateOwnShelfStateProjectionTests/' not in row['method'])
        self.assertEqual(actual_bindings, list(expected))

    def test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target(self):
        for mode in ['missing', 'duplicate', 'swapped', 'wrong-target', 'extra', 'unknown']:
            mutant = copy.deepcopy(SELECTION); rows = mutant['groups'][0]['method_sources']
            if mode == 'missing': rows.pop()
            elif mode == 'duplicate': rows[0] = rows[1]
            elif mode == 'swapped': rows[0]['source'] = 'Tests/CoreTests/ProfileEditTests.swift' if rows[0]['source'] != 'Tests/CoreTests/ProfileEditTests.swift' else 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'
            elif mode == 'wrong-target': rows[0]['source'] = 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'
            elif mode == 'extra': rows.append(copy.deepcopy(rows[0]))
            else: rows[0]['source'] = 'Tests/CoreTests/Unknown.swift'
            pin = runner.hashlib.sha256(runner.encode(mutant).encode()).hexdigest()
            with self.subTest(mode=mode), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaises(ValueError):runner.validate_selection(mutant, SOURCE)

    def test_repinned_changed_method_and_duplicate_source_declaration_fail(self):
        mutant = copy.deepcopy(SELECTION); group = mutant['groups'][0]
        old = group['methods'][0]; changed = old + 'Other'
        group['methods'][0] = changed
        group['method_sources'][0]['method'] = changed
        group['methods'].sort(); group['method_sources'].sort(key=lambda row: row['method'])
        pin = runner.hashlib.sha256(runner.encode(mutant).encode()).hexdigest()
        with mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaisesRegex(ValueError, 'fixed method/source identity'):
            runner.validate_selection(mutant, SOURCE)
        mutant = copy.deepcopy(SELECTION); path = SOURCE / mutant['groups'][0]['method_sources'][0]['source']
        text = path.read_text(); duplicate = text + '\n' + text
        for row in mutant['source_files']:
            if row['path'] == str(path.relative_to(SOURCE)): row['sha256'] = runner.hashlib.sha256(duplicate.encode()).hexdigest()
        pin = runner.hashlib.sha256(runner.encode(mutant).encode()).hexdigest()
        original_read = Path.read_text; original_digest = runner.digest
        def read(p, *args, **kwargs):return duplicate if p == path else original_read(p, *args, **kwargs)
        def digest(p):return runner.hashlib.sha256(duplicate.encode()).hexdigest() if p == path else original_digest(p)
        with mock.patch.object(Path, 'read_text', read), mock.patch.object(runner, 'digest', digest), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaisesRegex(ValueError, 'not uniquely declared'):
            runner.validate_selection(mutant, SOURCE)

    def test_duplicate_declaration_is_not_a_unique_method(self):
        source = 'final class Example: XCTestCase {\nfunc testOne() {}\nfunc testOne() {}\n}'
        self.assertEqual(runner.declared_methods(source, 'QuestifyCoreTests')['QuestifyCoreTests/Example/testOne'], 2)

    def test_nonboolean_version_and_exact_contract(self):
        for key, value in [('version', True), ('base_commit', 'a' * 40), ('base_tree', 'b' * 40),
                           ('name', 'all-tests'), ('branch', 'main'), ('repository', 'other/repo')]:
            mutant = copy.deepcopy(SELECTION); mutant[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_changed_source_hash_and_missing_guard_rejected(self):
        for mutation in ['change', 'missing', 'extra']:
            mutant = copy.deepcopy(SELECTION)
            if mutation == 'change': mutant['source_files'][0]['sha256'] = '0' * 64
            elif mutation == 'missing': mutant['source_files'].pop()
            else: mutant['source_files'].append({'path': '../private', 'sha256': '0' * 64})
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_empty_duplicate_target_and_wildcard_selectors_rejected(self):
        for mutation in ['empty', 'duplicate', 'target', 'wildcard', 'class', 'other-source', 'new-method']:
            mutant = copy.deepcopy(SELECTION); group = mutant['groups'][1]
            if mutation == 'empty': group['methods'] = []
            elif mutation == 'duplicate': group['methods'][0] = group['methods'][1]
            elif mutation == 'target': group['target'] = 'QuestifyUITests'
            elif mutation == 'wildcard': group['methods'][0] = 'QuestifyAppUnitTests/*/*'
            elif mutation == 'class': group['methods'][0] = 'QuestifyAppUnitTests/TemplateShelfReadCompositionTests'
            elif mutation == 'other-source': group['method_sources'][0]['source'] = 'Core/TemplateAuthoringShelf.swift'
            else: group['methods'][0] += 'Other'
            group['methods'].sort()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                runner.validate_selection(mutant, SOURCE)

    def test_core_filter_is_exact_set_without_full_suite_fallback(self):
        group = SELECTION['groups'][0]; command = runner.core_command(group, '/tmp/result.xml')
        pattern = re.compile(command[command.index('--filter') + 1])
        for method in group['methods']:
            swift_id = method.replace('/', '.', 1)
            self.assertIsNotNone(pattern.fullmatch(swift_id))
            for extra in ['Extra', '/extra', '()']:
                self.assertIsNone(pattern.fullmatch(swift_id + extra))
        self.assertIsNone(pattern.fullmatch('QuestifyCoreTests.TemplateAuthoringHTTPTests/testChangedBaselinePreventsWrite'))
        self.assertEqual(command[command.index('--num-workers') + 1], '1')
        with self.assertRaises(ValueError): runner.core_command({'methods': []}, '/tmp/result.xml')

    def test_every_xcode_method_has_its_own_exact_filter(self):
        for group in SELECTION['groups'][1:]:
            command = runner.xcode_test_command(group, '/tmp/one.xctestrun', UUID, '/tmp/one.xcresult')
            self.assertEqual([s for s in command if s.startswith('-only-testing:')], ['-only-testing:' + m for m in group['methods']])
            self.assertEqual(command.count('-destination'), 1)
            self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')
            self.assertEqual(command[command.index('-maximum-concurrent-test-simulator-destinations') + 1], '1')
            self.assertEqual(command[-1], 'test-without-building')
            self.assertNotIn('-allowProvisioningUpdates', command)

    def test_workflow_remains_additive_standard_and_independent(self):
        path = TOOLS.parent / '.github/workflows/native-targeted.yml'; text = path.read_text()
        active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        self.assertEqual(re.findall(r'^    runs-on: (.*)$', active, re.M), ['macos-26'])
        self.assertEqual(re.findall(r'^  (\w+):$', active.split('jobs:', 1)[1], re.M), ['targeted'])
        self.assertIn('branches: [migration/native-ios]', active)
        self.assertEqual(re.findall(r'^      - (.+)$', active.split('permissions:', 1)[0], re.M), list(runner.PATHS))
        self.assertIn('  workflow_dispatch:', active)
        self.assertIn('  contents: read', active)
        self.assertIn('persist-credentials: false', active)
        self.assertIn('GIT_TERMINAL_PROMPT=0 git -c credential.helper= fetch --no-tags --depth=1 https://github.com/liboyang42-cpu/chengyin-ios.git ' + runner.HISTORICAL_BASE_COMMIT, active)
        self.assertIn('timeout-minutes: 45', active)
        self.assertIn('name: native-targeted-diagnostic', active)
        for forbidden in ['needs:', 'matrix:', 'upload-artifact', 'download-artifact', 'secrets.', 'required-native-gates', 'run_static_checks.py', 'ci_gates.py aggregate']:
            self.assertNotIn(forbidden, active)
        self.assertNotIn('group: native-ios-', active)

    def test_original_gates_project_schemes_and_product_sources_are_unchanged(self):
        for row in SELECTION['source_files']:
            self.assertEqual(runner.digest(SOURCE / row['path']), row['sha256'], row['path'])
        old = (SOURCE / '.github/workflows/native-ios.yml').read_text()
        self.assertIn('needs: static-checks', old)
        self.assertIn('needs: [static-checks, native, device-build, us-build, secrets, app-unit-tests, ui-tests]', old)
        self.assertIn('name: native\n', old)
        self.assertIn('SHARD_COUNT = 79', (SOURCE / 'tools/ci_gates.py').read_text())


class ReviewedCompileRepair(unittest.TestCase):
    def test_complete_predecessors_and_unrelated_contract_semantics_are_preserved(self):
        restored = runner.validate_reviewed_repairs(SELECTION, SOURCE)
        self.assertEqual(set(restored), set(runner.REPAIR_PATHS))
        self.assertEqual(runner.hashlib.sha256(restored[runner.REPAIR_PATHS[1]]).hexdigest(),
                         'b5dff5b209ce495bb46075dcc514a20ebd2e4561a9d1ea3aadb02b02f8d393c9')
        old = restored[runner.REPAIR_PATHS[0]].decode()
        current = (SOURCE / runner.REPAIR_PATHS[0]).read_text()
        hunk = SELECTION['reviewed_repairs'][0]['hunks'][0]
        self.assertEqual(current.replace(hunk['after'], '<STATE>'), old.replace(hunk['before'], '<STATE>'))
        self.assertEqual(re.findall(r'@State private var (\w+)=(\d+\.\d+)', current), [('horizontal', '0.5'), ('vertical', '0.5'), ('zoom', '1.0')])
        self.assertNotRegex(current, r'@State[^\n]*,')
        self.assertEqual(runner.digest(SOURCE / 'tools/run138_current_source_projection.py'),
                         'c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727')

    def test_real_central_projection_accepts_current_support_and_exact_inverse(self):
        def load(path, name):
            spec = importlib.util.spec_from_file_location(name, path)
            module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            return module
        current = load(TOOLS / 'run138_editor_readiness.py', 'targeted_current_readiness')
        projection = load(SOURCE / 'tools/run138_current_source_projection.py', 'targeted_current_projection')
        path = runner.REPAIR_PATHS[0]; row = SELECTION['reviewed_repairs'][0]
        with mock.patch.object(projection, 'planning', return_value=current):
            projection.validate_feature_batch_sources(SOURCE)
            old = projection.original_feature_batch_bytes(path, (SOURCE / path).read_bytes(), SOURCE)
            self.assertEqual(runner.hashlib.sha256(old).hexdigest(), row['before_sha256'])
            for raw in [old, (SOURCE / path).read_bytes() + b'\n']:
                with self.assertRaises(ValueError): projection.original_feature_batch_bytes(path, raw, SOURCE)
            changed = copy.deepcopy(current.contract(SOURCE))
            changed['feature_batch_support_sha256'][path] = row['before_sha256']
            with mock.patch.object(current, 'contract', return_value=changed), self.assertRaises(ValueError):
                projection.validate_feature_batch_sources(SOURCE)
            changed = copy.deepcopy(current.contract(SOURCE)); del changed['feature_batch_sources'][path]
            with mock.patch.object(runner, 'read_json', return_value=changed), self.assertRaises((ValueError, KeyError)):
                runner.validate_reviewed_repairs(SELECTION, SOURCE)

    def test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage(self):
        for row in SELECTION['reviewed_repairs']:
            raw = (SOURCE / row['path']).read_bytes()
            for mutant in [raw + b'\n', raw.replace(row['hunks'][0]['after'].encode(), b'', 1),
                           raw + row['hunks'][0]['after'].encode()]:
                forged = copy.deepcopy(row); forged['after_sha256'] = runner.hashlib.sha256(mutant).hexdigest()
                with self.subTest(path=row['path']), self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged, mutant)
        for mode in ['missing', 'extra', 'support']:
            changed = copy.deepcopy(SELECTION)
            if mode == 'missing': changed['reviewed_repairs'].pop()
            elif mode == 'extra': changed['reviewed_repairs'].append(copy.deepcopy(changed['reviewed_repairs'][0]))
            else: changed['reviewed_repairs'][0]['after_sha256'] = '0' * 64
            with self.assertRaises(ValueError): runner.validate_selection(changed, SOURCE)


class Results(unittest.TestCase):
    def setUp(self):
        self.group = SELECTION['groups'][1]
        self.rows = [{'method': m, 'status': 'Passed'} for m in self.group['methods']]

    def test_xunit_reads_all_forty_four_real_cases(self):
        methods = SELECTION['groups'][0]['methods']
        xml = '<testsuites><testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '()" />' for m in methods) + '</testsuite></testsuites>'
        rows = runner.parse_xunit(xml.encode()); runner.validate_outcomes(rows, methods, 0)
        self.assertEqual(len(rows), 44)

    def test_core_transcript_proves_execution_beyond_swiftpm_xunit(self):
        methods = SELECTION['groups'][0]['methods']
        xml = ('<testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '" />' for m in methods) + '</testsuite>').encode()
        rows = runner.validate_core_evidence(xml, core_transcript(methods), methods, 0)
        self.assertEqual(len(rows), 44)
        # SwiftPM's successful child process xUnit looks identical for XCTSkip
        # and for a discovered method whose child process executes zero cases.
        mutants = [b'', b'Executed 0 tests, with 0 failures.\n', core_transcript(methods, 'skipped'),
                   core_transcript(methods, 'failed'), core_transcript(methods[:-1]),
                   core_transcript(methods + methods[:1]), core_transcript(methods).replace(b'started.', b'unknown.'),
                   core_transcript(methods).replace(b'QuestifyCoreTests.', b'OtherTarget.'),
                   core_transcript(methods).replace(b'started.\n', b'')]
        for transcript in mutants:
            with self.subTest(transcript=transcript[:90]), self.assertRaises(ValueError):
                runner.validate_core_evidence(xml, transcript, methods, 0)
        self.assertIn('--verbose', runner.core_command(SELECTION['groups'][0], '/tmp/result.xml'))
        self.assertIn('--skip-build', runner.core_command(SELECTION['groups'][0], '/tmp/result.xml'))

    def test_xunit_failures_skips_and_unknown_status_cannot_pass(self):
        for child in ['<failure/>', '<error/>', '<skipped/>']:
            xml = '<testsuite><testcase classname="QuestifyCoreTests.Example" name="testOne">' + child + '</testcase></testsuite>'
            rows = runner.parse_xunit(xml.encode())
            with self.assertRaises(ValueError): runner.validate_outcomes(rows, ['QuestifyCoreTests/Example/testOne'], 0)
        for xml in [b'<unknown/>', b'<testsuite><testcase classname="Wrong.Example" name="testOne"/></testsuite>', b'<testsuite><testcase classname="QuestifyCoreTests.Example" name="testOne" status="skipped"/></testsuite>']:
            with self.assertRaises(ValueError): runner.parse_xunit(xml)

    def test_modern_xcresult_exact_target_and_method_set(self):
        rows = runner.parse_xcresult(xctests(self.group['methods'], self.group['target']), self.group['target'])
        self.assertEqual(rows, self.rows)
        runner.validate_outcomes(rows, self.group['methods'], 0)
        runner.validate_summary(summary(12), 12, UUID)

    def test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema(self):
        for mutation in ['schema', 'target', 'method', 'status']:
            data = xctests(self.group['methods'], self.group['target'])
            bundle = data['testNodes'][0]['children'][0]; case = bundle['children'][0]
            if mutation == 'schema': data = {'other': data['testNodes']}
            elif mutation == 'target': bundle['name'] = 'QuestifyUITests'
            elif mutation == 'method': case['nodeIdentifier'] = 'UnknownTarget/Class/testOther'
            else: del case['result']
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])

    def test_target_url_binding_must_not_override_wrong_bundle(self):
        data = xctests(self.group['methods'], self.group['target']); case = data['testNodes'][0]['children'][0]['children'][0]
        case['nodeIdentifierURL'] = 'test://com.apple.xcode/Questify/' + self.group['methods'][0] + '()'
        self.assertEqual(runner.parse_xcresult(data, self.group['target']), self.rows)
        case['nodeIdentifierURL'] = case['nodeIdentifierURL'].replace('QuestifyAppUnitTests', 'QuestifyUITests')
        with self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])

    def test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail(self):
        mutants = [[], self.rows[:-1], self.rows + self.rows[:1], self.rows + [{'method': 'QuestifyAppUnitTests/Other/testExtra', 'status': 'Passed'}]]
        for status in ['Skipped', 'Failed', 'Expected Failure', 'Unknown', 'Cancelled']:
            rows = copy.deepcopy(self.rows); rows[0]['status'] = status; mutants.append(rows)
        for rows in mutants:
            with self.assertRaises(ValueError): runner.validate_outcomes(rows, self.group['methods'], 0)
        for code in [1, 65, 124, -2, -9]:
            with self.assertRaises(ValueError): runner.validate_outcomes(self.rows, self.group['methods'], code)

    def test_hidden_repetitions_and_xunit_summary_disagreement_fail(self):
        data = xctests(self.group['methods'], self.group['target'])
        case = data['testNodes'][0]['children'][0]['children'][0]
        case['children'] = [{'nodeType': 'Test Case', 'name': 'hidden', 'result': 'Failed'}]
        with self.assertRaises(ValueError): runner.parse_xcresult(data, self.group['target'])
        for attributes in ['tests="0"', 'tests="1" failures="1"', 'tests="1" skipped="1"']:
            raw = ('<testsuite ' + attributes + '><testcase classname="QuestifyCoreTests.Example" name="testOne"/></testsuite>').encode()
            with self.assertRaises(ValueError): runner.parse_xunit(raw)
        with self.assertRaises(ValueError): runner.validate_outcomes(self.rows, self.group['methods'], False)

    def test_summary_counts_actual_device_and_no_boolean_counts(self):
        for key, value in [('totalTestCount', 0), ('passedTests', 11), ('failedTests', 1), ('skippedTests', 1), ('expectedFailures', 1), ('totalTestCount', True), ('devicesAndConfigurations', [])]:
            mutant = summary(12); mutant[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): runner.validate_summary(mutant, 12, UUID)
        with self.assertRaises(ValueError): runner.validate_summary(summary(12), 12, 'OTHER')


class RuntimeBoundaries(unittest.TestCase):
    def test_single_installed_iphone_and_no_automatic_other_device(self):
        data = {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{'name': 'iPhone 17', 'udid': UUID, 'isAvailable': True}],
                            'com.apple.CoreSimulator.SimRuntime.tvOS-26-0': [{'name': 'iPhone wrong', 'udid': UUID, 'isAvailable': True}]}}
        self.assertEqual(runner.choose_simulator(data)['udid'], UUID)
        for mutant in [{}, {'devices': {}}, {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{'name': 'iPad', 'udid': UUID, 'isAvailable': True}]}}]:
            with self.assertRaises(ValueError): runner.choose_simulator(mutant)

    def test_run_requires_hosted_mac_exact_repo_branch_and_event(self):
        environment = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted', 'GITHUB_REPOSITORY': 'liboyang42-cpu/chengyin-ios', 'GITHUB_REF': 'refs/heads/migration/native-ios', 'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1'}
        with mock.patch.object(sys, 'platform', 'darwin'):
            runner.runtime_environment(environment)
            for key, value in [('RUNNER_ENVIRONMENT', 'self-hosted'), ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_RUN_ID', '0'), ('GITHUB_RUN_ATTEMPT', '')]:
                mutant = dict(environment); mutant[key] = value
                with self.assertRaises(ValueError): runner.runtime_environment(mutant)
        with mock.patch.object(sys, 'platform', 'linux'), self.assertRaises(ValueError): runner.runtime_environment(environment)

    def test_process_exit_is_real_and_timeout_never_passes(self):
        code, data = runner.execute([sys.executable, '-c', 'print("small")'], SOURCE, 5, True)
        self.assertEqual((code, data.strip()), (0, b'small'))
        code, _ = runner.execute([sys.executable, '-c', 'import time; time.sleep(60)'], SOURCE, .03, True)
        self.assertEqual(code, 124)
        with self.assertRaises(ValueError): runner.execute(['not-run'], SOURCE, 0)

    def test_core_build_is_once_before_exact_execution_and_failure_stops(self):
        class StopAfterCore(Exception):
            pass
        identity = {'source_sha': 'a' * 40, 'source_tree': 'b' * 40}
        environment = {'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_WORKFLOW_SHA': 'a' * 40}
        for code in [0, 1, 124]:
            with tempfile.TemporaryDirectory() as temporary:
                job = runner.Diagnostic(TOOLS.parent, Path(temporary), SELECTION)
                order = []
                def command(args, seconds, capture=False):
                    order.append(('build', args, seconds, capture))
                    return code, b''
                def collect(group, args, seconds, result):
                    order.append(('test', args, seconds))
                    raise StopAfterCore()
                with mock.patch.object(runner, 'runtime_environment'), mock.patch.object(runner, 'verify_scope', return_value=identity), mock.patch.dict(os.environ, environment), mock.patch.object(job, 'toolchain', return_value={}), mock.patch.object(job, 'command', side_effect=command), mock.patch.object(job, 'collect', side_effect=collect):
                    with self.assertRaises(StopAfterCore if code == 0 else ValueError): job.run()
                self.assertEqual(order[0], ('build', ['swift', 'build', '--build-tests'], 720, False))
                self.assertEqual([item[0] for item in order], ['build', 'test'] if code == 0 else ['build'])
                self.assertEqual(job.receipt['groups']['core']['build_returncode'], code)
                if code == 0:
                    self.assertEqual(order[1][1], runner.core_command(SELECTION['groups'][0], Path(temporary) / 'core.xml'))
                    self.assertEqual(order[1][2], 180)
                self.assertEqual(job.receipt['groups']['core']['actual_count'], 0)

    def test_core_capture_keeps_stderr_live_and_limits_only_evidence(self):
        process = mock.Mock(); process.returncode = 0
        process.communicate.return_value = (b'small XCTest transcript', None)
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process) as popen:
            self.assertEqual(runner.execute(['swift', 'test', '--skip-build'], SOURCE, 5, 'stdout'),
                             (0, b'small XCTest transcript'))
            self.assertEqual(popen.call_args.kwargs['stdout'], subprocess.PIPE)
            self.assertIsNone(popen.call_args.kwargs['stderr'])
        process.communicate.return_value = (b'x' * (runner.LIMIT + 1), None)
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process), self.assertRaises(ValueError):
            runner.execute(['fake'], SOURCE, 5, 'stdout')
        source = (TOOLS / 'run_targeted_native.py').read_text()
        self.assertIn("self.command(['swift', 'build', '--build-tests'], 720)", source)
        self.assertIn("self.collect(groups['core'], core_command(groups['core'], core), 180, core)", source)

    def test_every_cleanup_wait_is_bounded_even_after_kill(self):
        process = mock.Mock(); process.pid = 10
        process.communicate.side_effect = [subprocess.TimeoutExpired('fake', 1)] * 4
        with mock.patch.object(runner.subprocess, 'Popen', return_value=process), mock.patch.object(runner.os, 'killpg') as kill:
            with self.assertRaises(RuntimeError): runner.execute(['fake'], SOURCE, 1)
            self.assertEqual([c.kwargs['timeout'] for c in process.communicate.call_args_list], [1, 20, 10, 5])
            self.assertEqual([c.args[1] for c in kill.call_args_list], [signal.SIGINT, signal.SIGTERM, signal.SIGKILL])

    def test_product_target_selection_supports_only_safe_testhost_tokens(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); host = root / 'Debug/Questify.app'; bundle = host / 'PlugIns/QuestifyAppUnitTests.xctest'; bundle.mkdir(parents=True)
            path = root / 'app.xctestrun'
            value = {'TestTargets': [{'TestBundlePath': '__TESTHOST__/PlugIns/QuestifyAppUnitTests.xctest', 'TestHostPath': '__TESTROOT__/Debug/Questify.app'}]}
            path.write_bytes(plistlib.dumps(value))
            self.assertEqual(runner.select_xctestrun(root, 'QuestifyAppUnitTests'), path.resolve())
            for target in ['QuestifyUITests', 'Other']:
                with self.assertRaises(ValueError): runner.select_xctestrun(root, target)
            value['TestTargets'][0]['TestHostPath'] = '/etc'; path.write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyAppUnitTests')

    def test_product_directory_alias_returns_canonical_safe_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); products = root / 'actual'; products.mkdir()
            (products / 'QuestifyUITests.xctest').mkdir()
            run = products / 'ui.xctestrun'
            run.write_bytes(plistlib.dumps({'tests': [{'TestBundlePath': '__TESTROOT__/QuestifyUITests.xctest'}]}))
            alias = root / 'alias'; alias.symlink_to(products, target_is_directory=True)
            self.assertEqual(runner.select_xctestrun(alias, 'QuestifyUITests'), run.resolve())
            escaped = products / 'linked.xctestrun'; escaped.symlink_to(run)
            with self.assertRaises(ValueError): runner.select_xctestrun(alias, 'QuestifyUITests')

    def test_ambiguous_products_and_extra_target_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'QuestifyUITests.xctest').mkdir()
            value = {'tests': [{'TestBundlePath': str(root / 'QuestifyUITests.xctest')}]}
            for name in ['one', 'two']: (root / (name + '.xctestrun')).write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyUITests')
            (root / 'two.xctestrun').unlink(); value['tests'].append({'TestBundlePath': '/elsewhere/Other.xctest'})
            (root / 'one.xctestrun').write_bytes(plistlib.dumps(value))
            with self.assertRaises(ValueError): runner.select_xctestrun(root, 'QuestifyUITests')

    def test_inventory_detects_product_mutation_and_escaping_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'binary').write_bytes(b'one')
            before = runner.products_digest(root); (root / 'binary').write_bytes(b'two')
            self.assertNotEqual(before, runner.products_digest(root))
            (root / 'escaped').symlink_to('/etc')
            with self.assertRaises(ValueError): runner.products_digest(root)

    def test_scope_requires_exact_sha_base_and_nineteen_exact_statuses(self):
        output = scope_transport
        with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=output):
            self.assertEqual(runner.verify_scope(SOURCE, SELECTION)['source_tree'], 'b' * 40)
        for field in ['head', 'base', 'diff', 'dirty', 'missing-repair', 'wrong-status', 'old-additions', 'duplicate']:
            def mutated(command, root):
                original = output(command, root)
                if field == 'head' and command[1:3] == ['rev-parse', 'HEAD']: return 'c' * 40
                if field == 'base' and command[1:3] == ['rev-parse', runner.HISTORICAL_BASE_COMMIT + '^{tree}']: return 'c' * 40
                if field == 'diff' and command[1] == 'diff': return original + '\nM\tApp/AppSession.swift'
                if field == 'missing-repair' and command[1] == 'diff': return '\n'.join(original.splitlines()[:-1])
                if field == 'wrong-status' and command[1] == 'diff': return original.replace('M\t' + runner.CREATOR_PATHS[0], 'A\t' + runner.CREATOR_PATHS[0])
                if field == 'old-additions' and command[1] == 'diff': return original.replace('M\t' + runner.PATHS[0], 'A\t' + runner.PATHS[0])
                if field == 'duplicate' and command[1] == 'diff': return original + '\n' + original.splitlines()[0]
                if field == 'dirty' and command[1] == 'status': return ' M App/AppSession.swift'
                return original
            with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=mutated), self.assertRaises(ValueError):
                runner.verify_scope(SOURCE, SELECTION)

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'bad.json'; path.write_text('{"status":"FAIL","status":"PASS"}')
            with self.assertRaises(ValueError): runner.read_json(path)

    def test_missing_receipt_reports_not_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); destination = root / 'summary'
            runner.report(root, destination)
            self.assertIn('NOT_RUN', destination.read_text())
            self.assertNotIn('PASS', destination.read_text())


class ReceiptIdentity(unittest.TestCase):
    def receipt(self):
        identity = {'source_sha': 'a' * 40, 'source_tree': 'b' * 40, 'workflow_sha': 'a' * 40,
                    'run_id': '123', 'run_attempt': '1', 'selection_sha256': 'c' * 64}
        r = {**identity, 'version': 1, 'status': 'PASS', 'scope': 'selected-native-diagnostic-only',
             'base_commit': runner.BASE_COMMIT, 'base_tree': runner.BASE_TREE,
             'historical_base_commit': runner.HISTORICAL_BASE_COMMIT,
             'historical_base_tree': runner.HISTORICAL_BASE_TREE,
             'creator_base_commit': runner.CREATOR_COMMIT, 'creator_base_tree': runner.CREATOR_TREE,
             'selection': SELECTION['name'], 'expected_count': 65, 'actual_count': 65,
             'toolchain': {k: k for k in ['xcode', 'developer', 'swift', 'sdk_version', 'sdk_path']},
             'simulator': {'udid': UUID, 'name': 'iPhone 17', 'runtime': 'com.apple.CoreSimulator.SimRuntime.iOS-26-0'},
             'groups': {g['name']: {'status': 'PASS', 'expected': g['methods'], 'actual_count': len(g['methods']), 'returncode': 0,
                                   'actual': [{'method': m, 'status': 'Passed'} for m in g['methods']]} for g in SELECTION['groups']},
             'products': {}}
        r['groups']['core']['build_returncode'] = 0
        for name, config in [('ui', 'Debug/iphonesimulator/unsigned/ONLY_ACTIVE_ARCH=NO'), ('app-unit', 'Debug/iphonesimulator/isolated-entitlement-section/adhoc-host')]:
            r['products'][name] = {'configuration': config, 'files': 3, 'sha256': 'd' * 64, 'xctestrun_sha256': 'e' * 64}
        for group in SELECTION['groups']:
            for key in (['result_sha256', 'transcript_sha256'] if group['kind'] == 'swift' else ['summary_sha256', 'tests_sha256']):
                r['groups'][group['name']][key] = '9' * 64
        r['products']['app-unit']['manifest'] = {'commit': identity['source_sha'], 'purpose': 'isolated-simulator-app-unit',
            'toolchain': {k: r['toolchain'][k] for k in ['xcode', 'developer']}, 'source_archive_sha256': 'f' * 64}
        return r, identity

    def test_exact_same_run_sha_tree_configuration_and_65_results(self):
        receipt, identity = self.receipt(); runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_report_revalidates_real_exported_files_not_just_receipt_counts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / 'tools').mkdir(); output = root / 'results'; output.mkdir()
            selection_path = root / runner.PATHS[1]; runner.write_json(selection_path, SELECTION)
            receipt, identity = self.receipt(); receipt['selection_sha256'] = runner.digest(selection_path)
            methods = SELECTION['groups'][0]['methods']
            xml = '<testsuites><testsuite>' + ''.join('<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] + '" name="' + m.split('/')[2] + '()" />' for m in methods) + '</testsuite></testsuites>'
            (output / 'core.xml').write_text(xml); receipt['groups']['core']['result_sha256'] = runner.digest(output / 'core.xml')
            (output / 'core-stdout.txt').write_bytes(core_transcript(methods)); receipt['groups']['core']['transcript_sha256'] = runner.digest(output / 'core-stdout.txt')
            for group in SELECTION['groups'][1:]:
                for part, data in [('summary', summary(len(group['methods']))), ('tests', xctests(group['methods'], group['target']))]:
                    path = output / (group['name'] + '-' + part + '.json'); runner.write_json(path, data)
                    receipt['groups'][group['name']][part + '_sha256'] = runner.digest(path)
            runner.write_json(output / 'receipt.json', receipt)
            environment = {'GITHUB_SHA': identity['source_sha'], 'GITHUB_WORKFLOW_SHA': identity['workflow_sha'], 'GITHUB_RUN_ID': identity['run_id'], 'GITHUB_RUN_ATTEMPT': identity['run_attempt']}
            with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', return_value=identity['source_tree']), mock.patch('builtins.print'):
                runner.report(output, root / 'summary', root)
                self.assertIn('Actual methods: 65 / 65', (root / 'summary').read_text())
                transcript = output / 'core-stdout.txt'
                transcript.write_bytes(core_transcript(methods, 'skipped'))
                receipt['groups']['core']['transcript_sha256'] = runner.digest(transcript)
                runner.write_json(output / 'receipt.json', receipt)
                with self.assertRaises(ValueError): runner.report(output, None, root)
                transcript.write_bytes(core_transcript(methods))
                receipt['groups']['core']['transcript_sha256'] = runner.digest(transcript)
                runner.write_json(output / 'receipt.json', receipt)
                path = output / 'app-unit-tests.json'; changed = runner.read_json(path)
                changed['testNodes'][0]['children'][0]['children'][0]['result'] = 'Failed'; runner.write_json(path, changed)
                with self.assertRaises(ValueError): runner.report(output, None, root)
                receipt['groups']['app-unit']['tests_sha256'] = runner.digest(path); runner.write_json(output / 'receipt.json', receipt)
                with self.assertRaises(ValueError): runner.report(output, None, root)

    def test_other_run_attempt_sha_tree_selection_or_workflow_rejected(self):
        for key in ['run_id', 'run_attempt', 'source_sha', 'source_tree', 'selection_sha256', 'workflow_sha']:
            receipt, identity = self.receipt(); receipt[key] = 'different'
            with self.subTest(key=key), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected(self):
        for mode in ['config', 'toolchain', 'simulator', 'count', 'group', 'product-sha', 'archive', 'manifest-sha', 'result-sha', 'core-build']:
            receipt, identity = self.receipt()
            if mode == 'core-build': receipt['groups']['core']['build_returncode'] = 1
            elif mode == 'config': receipt['products']['ui']['configuration'] = 'Release/iphoneos'
            elif mode == 'toolchain': del receipt['toolchain']['sdk_version']
            elif mode == 'simulator': receipt['simulator']['name'] = 'iPad'
            elif mode == 'count': receipt['actual_count'] = 0
            elif mode == 'group': receipt['groups']['ui']['actual'] = []
            elif mode == 'product-sha': receipt['products']['ui']['sha256'] = ''
            elif mode == 'archive': receipt['products']['app-unit']['manifest']['source_archive_sha256'] = ''
            elif mode == 'result-sha': del receipt['groups']['core']['result_sha256']
            else: receipt['products']['app-unit']['manifest']['commit'] = 'z' * 40
            with self.subTest(mode=mode), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)


class CreatorCurrentTreeAndCounts(unittest.TestCase):
    def test_every_creator_current_tree_mode_blob_and_presence_is_exact(self):
        rows = SELECTION['creator_changes']
        records = ['100644 blob ' + r['after_blob'] + '\t' + r['path'] for r in rows]
        def verify(values):
            with mock.patch.object(runner, 'checked', return_value='\0'.join(values) + '\0') as check:
                result = runner.verify_creator_current_tree(SELECTION, SOURCE, 'a' * 40)
                check.assert_called_once_with(['git', 'ls-tree', '-z', 'a' * 40, '--', *runner.CREATOR_PATHS], SOURCE)
                return result
        self.assertEqual(len(verify(records)), 15)
        for i, row in enumerate(rows):
            for mode in ['missing', 'blob', 'executable', 'symlink', 'duplicate']:
                changed = list(records)
                if mode == 'missing': changed.pop(i)
                elif mode == 'duplicate': changed.append(changed[i])
                elif mode == 'blob': changed[i] = changed[i].replace(row['after_blob'], '0' * 40, 1)
                else: changed[i] = changed[i].replace('100644', '100755' if mode == 'executable' else '120000', 1)
                with self.subTest(path=row['path'], mode=mode), self.assertRaises(ValueError): verify(changed)
        with self.assertRaises(ValueError): verify(records + ['100644 blob ' + '0' * 40 + '\tCore/unknown.swift'])

    def test_receipt_counts_are_real_integers_and_outer_fields_are_exact(self):
        for field in ['expected_count', 'actual_count']:
            receipt, identity = ReceiptIdentity().receipt(); receipt[field] = 65.0
            with self.subTest(field=field), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)
        for group in ['core', 'app-unit', 'ui']:
            receipt, identity = ReceiptIdentity().receipt(); receipt['groups'][group]['actual_count'] = float(receipt['groups'][group]['actual_count'])
            with self.subTest(group=group), self.assertRaises(ValueError): runner.validate_pass_receipt(receipt, identity, SELECTION)
        changed = copy.deepcopy(SELECTION); changed['unknown_creator_field'] = True
        with mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', runner.hashlib.sha256(runner.encode(changed).encode()).hexdigest()), self.assertRaises(ValueError):
            runner.validate_selection(changed, SOURCE)


# Append before the existing ``if __name__ == '__main__'`` block.
# Expected identities are review-time literals, never derived from runner or SELECTION.
# Uses the existing test module imports, runner, SELECTION, SOURCE, core_transcript,
# UUID, and ReceiptIdentity. No Apple tools are executed.

LEGACY45_METHOD_SOURCES = (('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testDuplicateOverLimitHistoricalTagsStayUnchangedOnOpenCancelAndInvalidOwner',
  'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'),
 ('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testSemicolonTagApplyCancelAndReopenPreserveExactLabels',
  'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCurrent401ExpiresOnlyCurrentOwner',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority',
  'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'),
 ('QuestifyCoreTests/MerchantDecorTagDraftTests/testHistoricalLabelsRemainByteExactUntilExplicitRemoval',
  'Tests/CoreTests/MerchantDecorTagDraftTests.swift'),
 ('QuestifyCoreTests/MerchantDecorTagDraftTests/testSemicolonCustomLabelRemainsOneLiteralTag',
  'Tests/CoreTests/MerchantDecorTagDraftTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testAcknowledgedWriteReadbackFailureKeepsLockUntilReadOnlyRetry',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testCancelledReadDoesNotPublishLateServerExplanation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFailedRefreshRetainsSnapshotAndShowsExplanation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFinalPreWriteReadFailureDoesNotDispatchOrReuseConfirmation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testInitialReadFailureShowsExactServerMessageAndRetryClearsItWithoutWriting',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testLateFailureCannotPublishAfterSameAccountTokenReplacement',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testNewReadClearsPriorExplanationBeforeResponse',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testPrepareFailureKeepsSnapshotAndRequiresANewReview',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testSessionResetClearsPreviouslyDisplayedExplanation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnauthorizedCallbackInvalidatesFailureBeforePresentation',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnknownWriteReadbackFailureAndMatchingRetryNeverUnlockOrResend',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testWhitespaceAndNonServerErrorsNeverBecomeUserText',
  'Tests/CoreTests/ProfileEditTests.swift'),
 ('QuestifyCoreTests/TemplateAuthoringHTTPTests/testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testNewKeywordNeverDisplaysPreviousQuerySnapshot',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testSameKeywordNewGenerationRejectsOldSuccessAndError',
  'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testAccountChangeDismissesReviewAndSignoutClearsShelf',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testChineseLargeTextCanCancelReview',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testDefaultDisabledHasNoMutationConfirmation',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testDeleteRequiresSeparateReviewAndSimulationIsLabelled',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testOwnedDetailBackAndReopenKeepsStableDestination',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'),
 ('QuestifyUITests/TemplateOwnShelfFlowTests/testUnknownLocksBothActionsAcrossReopen',
  'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'))

CREATOR20_METHOD_SOURCES = (('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testActualMiniCounterexamplesSeparatePersonalAndMarketplaceStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testAlreadyCancelledRefreshCannotDispatchOrKeepSidecars',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testAuthContractAndCancellationErrorsClearEveryCachedState',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testCanonicalOptionalTextAndMissingFieldsRemainCompatible',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testDisplayMetadataNeverChangesSharedDTOOrAcknowledgesPendingMutation',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testEmptyFirstPageClearsRowsAndDisplayStatesTogether',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testExistingBaseDTOValidationIsNotRelaxedByTolerantDisplayColumns',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testFeedbackIsVerbatimOptionalTextAndNeverAnAction',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMalformedBaseRowsClearStatesWithoutCommittingPartialPage',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMalformedOptionalColumnsNeverInvalidateAnOtherwiseLegalRow',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMarketIdentityLongBoundsAreReadFromOriginalBytesWithoutCoercion',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMarketplaceMatrixIgnoresPersonalPublishStatus',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testNewKeywordCannotRetainOldStateWhenRequestFails',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testOldSuccessAndErrorCannotOverwriteNewSameIDState',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testOverlappingContinuationCannotPartiallyReplaceOrAppendStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testPartialMetadataDecodingDoesNotDropOtherFieldsOrOtherRows',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testPersonalReviewPrecedenceMatchesSourceMatrix',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testSameIDsAndEqualBaseRowsStillReplaceChangedDisplayStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testScopeTransitionsABARevocationLeaveAndCancelRetireStates',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'),
 ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testTransientRefreshRetainsStatesWithRowsAndRetryReplacesBoth',
  'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'))

# path -> (status, before_sha256, before_blob, after_sha256, after_blob)
CREATOR15_IDENTITIES = {'App/TemplateAuthoringMineView.swift': ('M',
                                         '91d2c740529dd2970568cacfcd68409618c6e2d1d6cda007daccfdb3dc8164d7',
                                         '35e95a15e1863941e78204e3529beb4fec75effd',
                                         '070653140719b1dd37b8cf5b811c0a6cfef9c66eff13fa06d9a78b6634a4c38f',
                                         '08cdc8e932d784043693e0def191b0e075d990ac'),
 'Core/TemplateAuthoringShelf.swift': ('M',
                                       '3d8865b315f1712f0056d1b376f0f7f2b1aa01e8417dab95f438c200cefe2e91',
                                       'bdf056d2be4425e27de9c05835844549e6bbd1e2',
                                       'a9261782a98016cf474bbd9a2b2035fd6fbba6bf5ac9bb5682f85c95f4bbb13a',
                                       '3833f06347f38410a385daeb30bc31137d56d1c8'),
 'Resources/Localizable.xcstrings': ('M',
                                     '6e9a854e14c29ad90a8b4ed88735e5641d15efc53ca810fb49dc366d3509910a',
                                     '941520db879d0dc32d15a66be6f053d07180a8c7',
                                     '8f552d5a3f34a86c19a370c411a08669dfb4440a15f3b3037cd635595b4ff995',
                                     'e7ef7d81d0b523d2c987cecca209b1db47a5e319'),
 'Tests/ContractChecks/test_template_shelf_state_projection.py': ('A',
                                                                  None,
                                                                  None,
                                                                  '92a11a1874c3c442ff7bf76d62ae4e8331e0d7d589f6d55d919e9a4130180dc4',
                                                                  'ce9f2f69217ec41a22b1c8f9162f8f13b29c7e8e'),
 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift': ('A',
                                                                None,
                                                                None,
                                                                'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87',
                                                                'e38e099587bfa2f13ce139fc0affec9956796d69'),
 'tools/tests/creator_shelf_state_history.py': ('A',
                                                None,
                                                None,
                                                '63d498f92184bfdf2349849c683347adc5766e73878cc1f5e86790b68799d2e3',
                                                '61690d3d2740f2644afe69bb882598d12ea550e3'),
 'tools/tests/test_creator_shelf_state_history.py': ('A',
                                                     None,
                                                     None,
                                                     '28e14028204276d0277afb29064d0f2ad65bcb05e57aadf226b63d61e606c924',
                                                     '7d87a62a590f0a43d22a50df0c28b82ccd3e1e87'),
 'tools/tests/creator_shelf_refresh_history.py': ('M',
                                                  'a0ccdaf793079c5dd59b5931d8d734f1d16856bbba7f8251125f1bc32b3c5c25',
                                                  'fd71251a812f05d4a0287ca743ee1f77d20c0a1c',
                                                  '55632e1d0235628b55478a6b50a5e5d369bf2c54d73f4d09ec33becf84b6d7e5',
                                                  '371bde68e2f41e19786bd24670daccf1a731eda8'),
 'tools/tests/test_creator_shelf_refresh_history.py': ('M',
                                                       'be30636bb1fde4a4c2d3f03078da7f80b49ab971fded3ededb5f6b80a93619e9',
                                                       '4be67258473f78cbec202c107f1e042304dbe4cc',
                                                       '26b98d87f9c465dd2e6cefbc31734e5925c13a86003a9e695a09f4b83ad36061',
                                                       '10ed339bdef2ed504ed0c1fe8084cc5941f1aecb'),
 'tools/tests/test_creator_pending_synthetic_storage_history.py': ('M',
                                                                   '608cef3c34c5b8590f93de52e787d9ac1e08aa1d6b0aa03e478f89ca31c1d85d',
                                                                   '73245573a05cebe9a9d870991738829f96c8822e',
                                                                   '8d4b8e0bf04a7ce28622b416956af3628348bf3f86d5af5630fe04bb07e7e739',
                                                                   '2f52a335789681737e99bbdb94758bafde49c0a7'),
 'tools/run138_editor_readiness_contract.json': ('M',
                                                 '519006c2f95083423c186d289b8b2a1b6ef9c6327b5fd461718548b8e0fc40ce',
                                                 'c4c827b956c3bb43d26ff17412dbc5ae92a35652',
                                                 'eb80d6bb10463819a30d41530cc00c909d94f6f79fd1108401b22031369b2053',
                                                 'aedee08391f8b84304c7ef23270810466f18b5e7'),
 'tools/run138_editor_readiness.py': ('M',
                                      'ab69d29bd7f410619ebd5b7a051bfe98ef239e4532a8466d5607f36ac24f3b08',
                                      'ef1277041b1cc3ff8a091794ec9e05051e5cbcbe',
                                      'a33058cdac0bfce6fe0c17f02059d0be061c5b3da0cd3df76ace1f856422662c',
                                      '3df054c632b4bb2923d2163cb7c95cba48e7502c'),
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': ('M',
                                                                        'd1d7ad397a76f668f47bcc4243c23a397d560e90220b01bd99dd91a85bfe3163',
                                                                        'a064deddd1f9e7a36c903e19c150b0407b81f227',
                                                                        'df08d6c30bcebd89e901e5ae3a5920b22142dbd8b2cf4a7dfa4c765be5917271',
                                                                        'ec967979d5473c2a07731e502c66ca3362611b75'),
 'App/MerchantBusinessEditor.swift': ('M',
                                      '37e4fb670565770a72f1c1ad0e1c5b2ac4affc35669514597c80790d4e8f394d',
                                      '5365e829dc0e668f407a0fd2411c1ac7a002352a',
                                      '13ff93a1d1608d0fc10cbbb1e2aa31b6f7b5496ea37553e052d147ab6611aff0',
                                      '542f1ee001f6e8210dbafd4e13ebd7796c316948'),
 'Tests/ContractChecks/test_merchant_review_draft_return.py': ('M',
                                                               'e9f31299585059f9ce7f6e23002bd815471f7ba85e83707fe9fd571934dd1968',
                                                               'aa3055d722502f962032bcf061882fed2e1bf21c',
                                                               'e5b7c6ce7d66037ed49dba6b32b59fcf213c57e24b6f8694285e7d612575d777',
                                                               'd6e31c58ae23fae4f9a1d8e2133f2628caca1933')}

DIAGNOSTIC4_PATHS = ('.github/workflows/native-targeted.yml', 'tools/targeted_native_selection.json', 'tools/run_targeted_native.py', 'tools/tests/test_targeted_native.py')

class Creator65Contract(unittest.TestCase):
    """Preserve all old coverage and authenticate the complete Creator15 layer."""

    @staticmethod
    def sha(raw):
        return runner.hashlib.sha256(raw).hexdigest()

    @staticmethod
    def blob(raw):
        return runner.hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()

    @staticmethod
    def xml(methods, skipped=None):
        return ('<testsuite tests="' + str(len(methods)) + '">' + ''.join(
            '<testcase classname="' + m.split('/')[0] + '.' + m.split('/')[1] +
            '" name="' + m.split('/')[2] + '()">' +
            ('<skipped/>' if m == skipped else '') + '</testcase>'
            for m in methods) + '</testsuite>').encode()

    def fixture_root(self):
        # Dereference source overlays only while making the fixture. Validation then
        # reads actual regular-file bytes; no read/digest/inverse function is mocked.
        temporary = tempfile.TemporaryDirectory(prefix='targeted-creator65-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        paths = {row['path'] for row in SELECTION['source_files']}
        paths.update(CREATOR15_IDENTITIES)
        paths.update(row['path'] for row in SELECTION['reviewed_repairs'])
        paths.update(runner.STATIC_REPAIR_PATHS)
        paths.update(runner.STATIC_DIAGNOSTIC_BASE_BLOBS)
        for relative in paths:
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((SOURCE / relative).read_bytes())
        return root

    def validate_repinned(self, selection, root):
        # Re-pinning just the outer document must never erase independent identities.
        pin = self.sha(runner.encode(selection).encode())
        with mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin):
            return runner.validate_selection(selection, root)

    def test_original_45_exact_bindings_plus_independent_20_are_exactly_65(self):
        self.assertEqual(len(LEGACY45_METHOD_SOURCES), 45)
        self.assertEqual(len(CREATOR20_METHOD_SOURCES), 20)
        self.assertFalse(set(LEGACY45_METHOD_SOURCES) & set(CREATOR20_METHOD_SOURCES))
        expected = sorted(LEGACY45_METHOD_SOURCES + CREATOR20_METHOD_SOURCES)
        self.assertEqual(len({m for m, _ in expected}), 65)
        actual = sorted((r['method'], r['source']) for g in SELECTION['groups']
                        for r in g['method_sources'])
        self.assertEqual(actual, expected)
        self.assertEqual(list(runner.FIXED_METHOD_SOURCES), expected)
        self.assertEqual([len(g['methods']) for g in SELECTION['groups']], [44, 14, 7])
        self.assertEqual([runner.GROUPS[k][2] for k in ('core', 'app-unit', 'ui')], [44, 14, 7])
        self.assertEqual(sorted(m for g in SELECTION['groups'] for m in g['methods']),
                         [m for m, _ in expected])
        self.assertEqual(sorted((m, p) for m, p in actual if (m, p) not in CREATOR20_METHOD_SOURCES),
                         list(LEGACY45_METHOD_SOURCES))
        self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), self.fixture_root()), SELECTION)

    def test_each_of_the_65_methods_has_one_declaration_in_its_exact_source(self):
        declarations = {}
        for method, source in LEGACY45_METHOD_SOURCES + CREATOR20_METHOD_SOURCES:
            target = method.split('/')[0]
            if (target, source) not in declarations:
                declarations[target, source] = runner.declared_methods((SOURCE / source).read_text(), target)
            with self.subTest(method=method, source=source):
                self.assertEqual(declarations[target, source].get(method), 1)
        source = 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'
        self.assertEqual(self.sha((SOURCE / source).read_bytes()),
                         'b2b199d73b7045d4c3de9ce7bc0ea41b10bfc233c6b9c180438fd415d5c99b87')
        self.assertEqual(declarations['QuestifyCoreTests', source],
                         {m: 1 for m, _ in CREATOR20_METHOD_SOURCES})

    def test_each_new_method_rejects_repinned_replacement_or_wrong_source(self):
        root = self.fixture_root()
        for method, source in CREATOR20_METHOD_SOURCES:
            for mode in ('replacement', 'wrong-source', 'missing-binding'):
                changed = copy.deepcopy(SELECTION)
                group = changed['groups'][0]
                row = next(r for r in group['method_sources'] if r['method'] == method)
                if mode == 'replacement':
                    group['methods'][group['methods'].index(method)] = method + 'Other'
                    row['method'] = method + 'Other'
                    group['methods'].sort()
                    group['method_sources'].sort(key=lambda r: r['method'])
                elif mode == 'wrong-source':
                    row['source'] = 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'
                else:
                    group['method_sources'].remove(row)
                with self.subTest(method=method, mode=mode), self.assertRaises(ValueError):
                    self.validate_repinned(changed, root)

    def test_each_new_declaration_is_checked_before_creator_image_validation(self):
        root = self.fixture_root()
        source = 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'
        path = root / source
        original = path.read_bytes()
        for method, _ in CREATOR20_METHOD_SOURCES:
            name = method.rsplit('/', 1)[1]
            for mode in ('missing', 'duplicate'):
                if mode == 'missing':
                    raw = original.replace(('func ' + name + '(').encode(),
                                           ('func removed_' + name + '(').encode(), 1)
                else:
                    raw = original + ('\nfunc ' + name + '() {}\n').encode()
                path.write_bytes(raw)
                changed = copy.deepcopy(SELECTION)
                next(r for r in changed['source_files'] if r['path'] == source)['sha256'] = self.sha(raw)
                with self.subTest(method=method, mode=mode), self.assertRaisesRegex(ValueError, 'not uniquely declared'):
                    self.validate_repinned(changed, root)
                path.write_bytes(original)

    def test_new_source_binding_cannot_be_dropped_even_after_outer_repin(self):
        changed = copy.deepcopy(SELECTION)
        source = 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'
        changed['source_files'] = [r for r in changed['source_files'] if r['path'] != source]
        with self.assertRaises(ValueError):
            self.validate_repinned(changed, self.fixture_root())

    def test_core_44_requires_both_complete_independent_execution_streams(self):
        methods = SELECTION['groups'][0]['methods']
        self.assertEqual(len(methods), 44)
        good_xml, good_stdout = self.xml(methods), core_transcript(methods)
        self.assertEqual(len(runner.validate_core_evidence(good_xml, good_stdout, methods, 0)), 44)
        for method, _ in CREATOR20_METHOD_SOURCES:
            missing = [m for m in methods if m != method]
            replaced = [m if m != method else m + 'Other' for m in methods]
            duplicate = [m if m != method else missing[0] for m in methods]
            skipped_stdout = good_stdout.replace(core_transcript([method]), core_transcript([method], 'skipped'))
            cases = (
                ('xml-missing', self.xml(missing), good_stdout),
                ('stdout-missing', good_xml, core_transcript(missing)),
                ('both-missing', self.xml(missing), core_transcript(missing)),
                ('xml-skip', self.xml(methods, skipped=method), good_stdout),
                ('stdout-skip', good_xml, skipped_stdout),
                ('xml-same-count-replacement', self.xml(replaced), good_stdout),
                ('stdout-same-count-replacement', good_xml, core_transcript(replaced)),
                ('both-same-count-replacement', self.xml(replaced), core_transcript(replaced)),
                ('both-same-count-duplicate', self.xml(duplicate), core_transcript(duplicate)),
            )
            for mode, xml, stdout in cases:
                with self.subTest(method=method, mode=mode), self.assertRaises(ValueError):
                    runner.validate_core_evidence(xml, stdout, methods, 0)
        for returncode in (1, 65, 124, False):
            with self.subTest(returncode=returncode), self.assertRaises(ValueError):
                runner.validate_core_evidence(good_xml, good_stdout, methods, returncode)

    def receipt65(self):
        receipt, identity = ReceiptIdentity().receipt()
        receipt['expected_count'] = receipt['actual_count'] = 65
        return receipt, identity

    def test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting(self):
        receipt, identity = self.receipt65()
        runner.validate_pass_receipt(receipt, identity, SELECTION)
        old_core = [m for m, _ in LEGACY45_METHOD_SOURCES if m.startswith('QuestifyCoreTests/')]
        self.assertEqual(len(old_core), 24)
        for mode in ('honest-45', 'forged-total-65', 'forged-core-44', 'forged-expected-44'):
            stale = copy.deepcopy(receipt)
            stale['expected_count'] = stale['actual_count'] = 45 if mode == 'honest-45' else 65
            core = stale['groups']['core']
            core['expected'] = old_core
            core['actual_count'] = 24
            core['actual'] = [{'method': m, 'status': 'Passed'} for m in old_core]
            if mode in ('forged-core-44', 'forged-expected-44'):
                core['actual_count'] = 44
            if mode == 'forged-expected-44':
                core['expected'] = SELECTION['groups'][0]['methods']
            # Source/run/selection identity intentionally remains the *new* identity:
            # rejection must survive relabelling an old execution as the new run.
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                runner.validate_pass_receipt(stale, identity, SELECTION)

    def test_each_new_method_is_required_in_the_65_receipt(self):
        receipt, identity = self.receipt65()
        for method, _ in CREATOR20_METHOD_SOURCES:
            for mode in ('missing', 'skipped', 'same-count-replacement'):
                changed = copy.deepcopy(receipt)
                core = changed['groups']['core']
                row = next(r for r in core['actual'] if r['method'] == method)
                if mode == 'missing':
                    core['actual'].remove(row)
                elif mode == 'skipped':
                    row['status'] = 'Skipped'
                else:
                    row['method'] = method + 'Other'
                with self.subTest(method=method, mode=mode), self.assertRaises(ValueError):
                    runner.validate_pass_receipt(changed, identity, SELECTION)

    def test_creator_15_and_diagnostic_4_have_exact_independent_statuses(self):
        self.assertEqual(runner.HISTORICAL_BASE_COMMIT, '45b728c7d48cf7969ac864e5693322d45e79394a')
        self.assertEqual(runner.HISTORICAL_BASE_TREE, '440cdc3bbd4a40369e6cb6762eec6306e4aa921d')
        self.assertEqual(tuple(runner.PATHS), DIAGNOSTIC4_PATHS)
        self.assertIsInstance(runner.CREATOR_PATHS, tuple)
        self.assertEqual(len(runner.CREATOR_PATHS), 15)
        self.assertEqual(set(runner.CREATOR_PATHS), set(CREATOR15_IDENTITIES))
        self.assertFalse(set(runner.CREATOR_PATHS) & set(DIAGNOSTIC4_PATHS))
        expected = {'M\t' + p for p in DIAGNOSTIC4_PATHS}
        expected.update(spec[0] + '\t' + p for p, spec in CREATOR15_IDENTITIES.items())
        self.assertIsInstance(runner.HISTORICAL_ALLOWED_CHANGES, tuple)
        self.assertEqual(len(runner.HISTORICAL_ALLOWED_CHANGES), 19)
        self.assertEqual(set(runner.HISTORICAL_ALLOWED_CHANGES), expected)
        self.assertEqual(SELECTION['historical_base']['allowed_changes'], list(runner.HISTORICAL_ALLOWED_CHANGES))
        self.assertEqual(sum(x.startswith('M\t') for x in runner.HISTORICAL_ALLOWED_CHANGES), 15)
        self.assertEqual(sum(x.startswith('A\t') for x in runner.HISTORICAL_ALLOWED_CHANGES), 4)

    def test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound(self):
        rows = SELECTION['creator_changes']
        self.assertEqual([r['path'] for r in rows], list(runner.CREATOR_PATHS))
        self.assertEqual(self.sha(runner.encode(rows).encode()), runner.CREATOR_CHANGES_CONTRACT_SHA256)
        root = self.fixture_root()
        published = runner.restore_creator_inputs(SELECTION, root)
        restored = runner.validate_creator_changes(SELECTION, root)
        self.assertEqual(set(restored), {p for p, spec in CREATOR15_IDENTITIES.items() if spec[0] == 'M'})
        for row in rows:
            path = row['path']
            with self.subTest(path=path):
                self.assertEqual(set(row), {'path', 'status', 'before_sha256', 'before_blob',
                                            'after_sha256', 'after_blob', 'hunks'})
                self.assertEqual(tuple(row[k] for k in ('status', 'before_sha256', 'before_blob',
                                                       'after_sha256', 'after_blob')),
                                 CREATOR15_IDENTITIES[path])
                raw = published.get(path, (root / path).read_bytes())
                self.assertEqual(self.sha(raw), row['after_sha256'])
                self.assertEqual(self.blob(raw), row['after_blob'])
                if row['status'] == 'A':
                    self.assertIsNone(row['before_sha256'])
                    self.assertIsNone(row['before_blob'])
                    self.assertEqual(row['hunks'], [])
                else:
                    self.assertTrue(row['hunks'])
                    self.assertEqual(restored[path], runner.inverse_reviewed_repair(row, raw))
                    self.assertEqual(self.sha(restored[path]), row['before_sha256'])
                    self.assertEqual(self.blob(restored[path]), row['before_blob'])

    def test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin(self):
        root = self.fixture_root()
        for mode in ('missing', 'duplicate', 'reordered', 'unknown-path', 'wrong-status',
                     'wrong-after-sha', 'wrong-after-blob', 'extra-key', 'missing-key'):
            changed = copy.deepcopy(SELECTION)
            rows = changed['creator_changes']
            if mode == 'missing':
                rows.pop()
            elif mode == 'duplicate':
                rows.append(copy.deepcopy(rows[0]))
            elif mode == 'reordered':
                rows.reverse()
            elif mode == 'unknown-path':
                rows[0]['path'] = 'Core/UnreviewedCreator.swift'
            elif mode == 'wrong-status':
                rows[0]['status'] = 'A' if rows[0]['status'] == 'M' else 'M'
            elif mode == 'wrong-after-sha':
                rows[0]['after_sha256'] = '0' * 64
            elif mode == 'wrong-after-blob':
                rows[0]['after_blob'] = '0' * 40
            elif mode == 'extra-key':
                rows[0]['ignored'] = True
            else:
                del rows[0]['after_blob']
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.validate_repinned(changed, root)

    def test_every_creator_path_rejects_changed_real_current_bytes(self):
        root = self.fixture_root()
        for path in CREATOR15_IDENTITIES:
            destination = root / path
            raw = destination.read_bytes()
            destination.write_bytes(raw + b'\n')
            with self.subTest(path=path), self.assertRaises(ValueError):
                runner.validate_creator_changes(SELECTION, root)
            destination.write_bytes(raw)
        # A successful final validation proves every temporary mutation was restored.
        self.assertEqual(len(runner.validate_creator_changes(SELECTION, root)), 11)

    def test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks(self):
        root = self.fixture_root()
        for path, spec in CREATOR15_IDENTITIES.items():
            if spec[0] != 'A':
                continue
            destination = root / path
            raw = destination.read_bytes()
            for mode in ('rehashed-current', 'before-sha', 'before-blob', 'hunks'):
                changed = copy.deepcopy(SELECTION)
                row = next(r for r in changed['creator_changes'] if r['path'] == path)
                if mode == 'rehashed-current':
                    mutant = raw + b'\n'
                    destination.write_bytes(mutant)
                    row['after_sha256'], row['after_blob'] = self.sha(mutant), self.blob(mutant)
                    for source in changed['source_files']:
                        if source['path'] == path:
                            source['sha256'] = self.sha(mutant)
                elif mode == 'before-sha':
                    row['before_sha256'] = self.sha(b'')
                elif mode == 'before-blob':
                    row['before_blob'] = self.blob(b'')
                else:
                    row['hunks'] = [{'before': '', 'after': raw.decode()}]
                with self.subTest(path=path, mode=mode), self.assertRaises(ValueError):
                    self.validate_repinned(changed, root)
                destination.write_bytes(raw)

    def test_modified_creator_inverse_requires_complete_predecessor(self):
        published = runner.restore_creator_inputs(SELECTION, SOURCE)
        for row in SELECTION['creator_changes']:
            if row['status'] != 'M':
                continue
            raw = published.get(row['path'], (SOURCE / row['path']).read_bytes())
            old = runner.inverse_reviewed_repair(row, raw)
            self.assertEqual(self.sha(old), CREATOR15_IDENTITIES[row['path']][1])
            self.assertEqual(self.blob(old), CREATOR15_IDENTITIES[row['path']][2])
            hunk = row['hunks'][0]
            for mutant in (raw + b'\n', raw.replace(hunk['after'].encode(), b'', 1),
                           raw + hunk['after'].encode()):
                forged = copy.deepcopy(row)
                forged['after_sha256'], forged['after_blob'] = self.sha(mutant), self.blob(mutant)
                with self.subTest(path=row['path']), self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged, mutant)

    def baseline_records(self):
        return ['100644 blob ' + spec[2] + '\t' + path
                for path, spec in CREATOR15_IDENTITIES.items() if spec[0] == 'M']

    def verify_synthetic_baseline(self, records, root):
        # Only the git transport is synthetic; independent pinned blob records are
        # parsed by the real function. All current files remain real byte fixtures.
        output = '\0'.join(records) + ('\0' if records else '')
        expected_command = ['git', 'ls-tree', '-z', runner.HISTORICAL_BASE_TREE, '--', *runner.CREATOR_PATHS]
        def checked(command, actual_root, *args, **kwargs):
            self.assertEqual(command, expected_command)
            self.assertEqual(actual_root, root)
            return output
        with mock.patch.object(runner, 'checked', side_effect=checked) as invoked:
            result = runner.verify_creator_baseline(SELECTION, root)
            self.assertEqual(invoked.call_count, 1)
            return result

    def test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent(self):
        root = self.fixture_root()
        records = self.baseline_records()
        self.assertEqual(len(records), 11)
        self.verify_synthetic_baseline(records, root)
        for path, spec in CREATOR15_IDENTITIES.items():
            if spec[0] == 'A':
                bad = records + ['100644 blob ' + spec[4] + '\t' + path]
                with self.subTest(path=path, mode='addition-already-exists'), self.assertRaises(ValueError):
                    self.verify_synthetic_baseline(bad, root)
            else:
                original = '100644 blob ' + spec[2] + '\t' + path
                for mode in ('missing', 'wrong-blob', 'executable', 'symlink', 'tree', 'duplicate'):
                    bad = list(records)
                    if mode == 'missing':
                        bad.remove(original)
                    elif mode == 'duplicate':
                        bad.append(original)
                    else:
                        replacement = {
                            'wrong-blob': '100644 blob ' + '0' * 40 + '\t' + path,
                            'executable': original.replace('100644', '100755', 1),
                            'symlink': original.replace('100644', '120000', 1),
                            'tree': original.replace('100644 blob', '040000 tree', 1),
                        }[mode]
                        bad[bad.index(original)] = replacement
                    with self.subTest(path=path, mode=mode), self.assertRaises(ValueError):
                        self.verify_synthetic_baseline(bad, root)
        with self.assertRaises(ValueError):
            self.verify_synthetic_baseline(records + ['100644 blob ' + '1' * 40 + '\tCore/Unreviewed.swift'], root)

    def test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin(self):
        root = self.fixture_root()
        for path in CREATOR15_IDENTITIES:
            for field, bad in (('after_sha256', '0' * 64), ('after_blob', '0' * 40)):
                changed = copy.deepcopy(SELECTION)
                row = next(r for r in changed['creator_changes'] if r['path'] == path)
                row[field] = bad
                inner_pin = self.sha(runner.encode(changed['creator_changes']).encode())
                with self.subTest(path=path, field=field), \
                     mock.patch.object(runner, 'CREATOR_CHANGES_CONTRACT_SHA256', inner_pin), \
                     self.assertRaisesRegex(ValueError, 'current creator (bytes|blob)'):
                    runner.validate_creator_changes(changed, root)

    def test_each_creator_current_file_must_exist_as_a_regular_checkout_file(self):
        root = self.fixture_root()
        for path in CREATOR15_IDENTITIES:
            destination = root / path
            raw = destination.read_bytes()
            destination.unlink()
            with self.subTest(path=path, mode='missing'), self.assertRaises((ValueError, OSError)):
                runner.validate_creator_changes(SELECTION, root)
            sibling = destination.with_name(destination.name + '.unchanged-fixture')
            sibling.write_bytes(raw)
            destination.symlink_to(sibling)
            with self.subTest(path=path, mode='same-bytes-symlink'), self.assertRaises(ValueError):
                runner.validate_creator_changes(SELECTION, root)
            destination.unlink()
            sibling.unlink()
            destination.write_bytes(raw)

    def test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced(self):
        root = self.fixture_root()
        for path, spec in CREATOR15_IDENTITIES.items():
            if spec[0] != 'A':
                continue
            for field, bad in (('before_sha256', self.sha(b'')), ('before_blob', self.blob(b'')),
                               ('hunks', [{'before': '', 'after': (root / path).read_text()}])):
                changed = copy.deepcopy(SELECTION)
                row = next(r for r in changed['creator_changes'] if r['path'] == path)
                row[field] = bad
                inner_pin = self.sha(runner.encode(changed['creator_changes']).encode())
                with self.subTest(path=path, field=field), \
                     mock.patch.object(runner, 'CREATOR_CHANGES_CONTRACT_SHA256', inner_pin), \
                     self.assertRaisesRegex(ValueError, 'fabricated predecessor'):
                    runner.validate_creator_changes(changed, root)


class ShallowCheckoutBoundaries(unittest.TestCase):
    def test_current_bytes_validate_without_history_but_real_run_scope_requires_it(self):
        root = Creator65Contract.fixture_root(self)
        with mock.patch.object(runner, 'checked', side_effect=AssertionError('Current validation must not read Git history')):
            self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), root), SELECTION)
        transport = scope_transport
        with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), \
             mock.patch.object(runner, 'checked', side_effect=transport), \
             mock.patch.object(runner, 'verify_creator_baseline', side_effect=ValueError('Historical baseline missing')) as baseline:
            with self.assertRaisesRegex(ValueError, 'Historical baseline missing'):
                runner.verify_scope(root, SELECTION)
            baseline.assert_called_once_with(SELECTION, root)

    def test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history(self):
        root = Creator65Contract.fixture_root(self)
        gitdir = root / 'witness.git'
        env = dict(os.environ, GIT_DIR=str(gitdir), GIT_INDEX_FILE=str(root / 'witness.index'))
        env.pop('GIT_OBJECT_DIRECTORY', None); env.pop('GIT_ALTERNATE_OBJECT_DIRECTORIES', None)
        subprocess.run(['git', 'init', '--bare', '-q', str(gitdir)], env=env, check=True)
        (root / '.git').write_text('gitdir: ' + str(gitdir) + '\n')
        def git(*args, data=None):
            return subprocess.check_output(['git', *args], input=data, env=env).decode().strip()
        git('read-tree', '--empty')
        published = runner.restore_creator_inputs(SELECTION, root)
        for row in SELECTION['creator_changes']:
            if row['status'] == 'M':
                old = runner.inverse_reviewed_repair(row, published.get(row['path'], (root / row['path']).read_bytes()))
                oid = git('hash-object', '-w', '--stdin', data=old)
                self.assertEqual(oid, row['before_blob'])
                git('update-index', '--add', '--cacheinfo', '100644', oid, row['path'])
        witness = git('write-tree')
        # This is an explicit disposable subset tree, not a claim to recreate45b.
        # The independent identity fixture still fixes the production full tree.
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(runner, 'HISTORICAL_BASE_TREE', witness):
            self.assertEqual(len(runner.verify_creator_baseline(SELECTION, root)), 11)
        for row in SELECTION['creator_changes']:
            if row['status'] != 'A': continue
            git('read-tree', witness)
            oid = git('hash-object', '-w', '--stdin', data=published.get(row['path'], (root / row['path']).read_bytes()))
            self.assertEqual(oid, row['after_blob'])
            git('update-index', '--add', '--cacheinfo', '100644', oid, row['path'])
            mutant = git('write-tree')
            with self.subTest(path=row['path']), mock.patch.dict(os.environ, env, clear=True), \
                 mock.patch.object(runner, 'HISTORICAL_BASE_TREE', mutant), self.assertRaisesRegex(ValueError, 'already exists in baseline'):
                runner.verify_creator_baseline(SELECTION, root)


class StaticRepairBinding(unittest.TestCase):
    """Current 3393 repair scope is independent of every preserved history layer."""
    BASELINES = {'App/ProjectThoughtDefinitionsEditor.swift': ('M',
                                               'dc2bcdecf846d8226db09d96df7ce7688cabc722249add64a114d48721263bd9',
                                               '01b97e6fa5bcfbda6ee476c8ec32bc17636cb27d'),
 'App/ProjectEndingConditionPicker.swift': ('M',
                                            '1b0a460cc65ee4ba69be25390940f188bbeaddbd824ee4d77d053dfdb28ba5a8',
                                            '6f9114ca362dac40dbfc1ae19c8947c133a44c3b'),
 'tools/run138_editor_readiness.py': ('M',
                                      'f39364ce7df89dc337047e825294047fa0af2f461424cd9aa1e6384c0c389d4f',
                                      'b59adab2ffde9df7d9ad3a3afc8e8e4084ee2bbb'),
 'tools/run138_editor_readiness_contract.json': ('M',
                                                 'b72d9b1024daadb5273a4de24c0175d42c04516b1f89c6c53c0f9c40dd7a77b6',
                                                 '045c337b9a9c36595192df7c46272ab487f4258b'),
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': ('M',
                                                                        'f9904bbd44d23bcaacd02be0647cf6bc4d7f0d5994371a8f05f2edac868b59ec',
                                                                        'be4ebdde8b93e24c2fb1833c16473598f8f6b9be'),
 'tools/club_customer_directory_admission.py': ('M',
                                                '80b6fb95961ef598ea66aa02e0081938b5df2ae7860a3e3fad76e5c0fa0a2297',
                                                '50e51bdc77a9373046c00c8313d3e45079cac76a'),
 'Tests/ContractChecks/test_category_roam_registration.py': ('M',
                                                             '80f4cbe6fba6df6ed1604aea7d7dfd20fd957d679a6e450401a49d2b80c5f1fa',
                                                             'b7403c238d4a70a362b86eb2a67627553c0958ef'),
 'tools/tests/test_creator_shelf_state_history.py': ('M',
                                                     'accaa341cf2803a6847c19ee675d7bb9d06b831d300c1a56d9f17d9aeddfb65e',
                                                     '53740f8ba2cf1f428f78da4309e7aeb883d06af6'),
 'tools/tests/test_club_parity_integration_budget.py': ('M',
                                                        'e2b27a07353c01261c3220596fa46376f77dd59b533a12caf9f3174fe279a248',
                                                        '48eee28519350c74cab77601b751db5de094c946'),
 'tools/tests/test_readiness_contract_parse_cache.py': ('A', None, None),
 'Tests/ContractChecks/test_global_search_category_recovery.py': ('M',
                                                                  '1cda598881ae8cd6327b8ef322337f78ca40d8f6c29f2a7d8b84b49050de591f',
                                                                  '375bee1d0b03f3d02bbe028b0a8b2ae69b984587'),
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py': ('M',
                                                                           'b1ee3e1eac62c6a670986301f1fe2713d615c7a8a82ece5dfdd8946ae08e43c1',
                                                                           'd5a1361846364539a119a558fd23459164a465cb')}

    def fixture_root(self):
        return Creator65Contract.fixture_root(self)

    def test_exact_published_base_nine_paths_and_old_domains_remain_separate(self):
        self.assertEqual(runner.BASE_COMMIT, '3393ec85076a7a4e246e94e98ddf81f6b73ede2f')
        self.assertEqual(runner.BASE_TREE, '7dd9461bafbe546e1c5ef5eaacc750267b416b2f')
        self.assertEqual(SELECTION['base_commit'], runner.BASE_COMMIT)
        self.assertEqual(SELECTION['base_tree'], runner.BASE_TREE)
        expected = {status + '\t' + path for path, (status, _, _) in self.BASELINES.items()}
        expected.update('M\t' + path for path in ('tools/targeted_native_selection.json',
                        'tools/run_targeted_native.py', 'tools/tests/test_targeted_native.py'))
        self.assertEqual(len(runner.ALLOWED_CHANGES), 15)
        self.assertEqual(set(runner.ALLOWED_CHANGES), expected)
        self.assertEqual(SELECTION['allowed_changes'], list(runner.ALLOWED_CHANGES))
        self.assertEqual([x for x in runner.ALLOWED_CHANGES if x.startswith('A\t')],
                         ['A\ttools/tests/test_readiness_contract_parse_cache.py'])
        self.assertNotIn('M\t.github/workflows/native-targeted.yml', runner.ALLOWED_CHANGES)
        self.assertEqual(tuple(runner.STATIC_REPAIR_PATHS), tuple(self.BASELINES))
        self.assertEqual(len(runner.HISTORICAL_ALLOWED_CHANGES), 19)
        self.assertEqual(SELECTION['historical_base'], {
            'base_commit': '45b728c7d48cf7969ac864e5693322d45e79394a',
            'base_tree': '440cdc3bbd4a40369e6cb6762eec6306e4aa921d',
            'allowed_changes': list(runner.HISTORICAL_ALLOWED_CHANGES)})
        self.assertEqual(runner.CREATOR_CHANGES_CONTRACT_SHA256,
                         'a0a916e50820419681f69c6e21ad048655f5b5d6db628079cc8a44a96ab7e1e9')
        for path in ('tools/tests/test_readiness_contract_parse_cache.py',
                     'tools/tests/test_club_parity_integration_budget.py'):
            self.assertNotIn(path, runner.CREATOR_PATHS)
            self.assertNotIn(path, runner.REPAIR_PATHS)
            self.assertNotIn(path, runner.BOUND_SOURCES)

    def test_complete_current_payload_inverts_to_independent_b75_bytes(self):
        root = self.fixture_root()
        restored = runner.validate_static_repair(SELECTION, root)
        self.assertEqual(set(restored), {p for p, row in self.BASELINES.items() if row[0] == 'M'})
        for row in SELECTION['static_repair_changes']:
            path = row['path']; raw = (root / path).read_bytes()
            with self.subTest(path=path):
                self.assertEqual(tuple(row[k] for k in ('status', 'before_sha256', 'before_blob')),
                                 self.BASELINES[path])
                self.assertEqual(Creator65Contract.sha(raw), row['after_sha256'])
                self.assertEqual(Creator65Contract.blob(raw), row['after_blob'])
                if row['status'] == 'M':
                    self.assertEqual(Creator65Contract.sha(restored[path]), self.BASELINES[path][1])
                    self.assertEqual(Creator65Contract.blob(restored[path]), self.BASELINES[path][2])
                    self.assertEqual(runner.inverse_reviewed_repair(row, raw), restored[path])
                else:
                    self.assertEqual(row['hunks'], [])
                    self.assertNotIn(path, restored)
        self.assertEqual(runner.validate_selection(copy.deepcopy(SELECTION), root), SELECTION)

    def test_manifest_cannot_widen_or_change_under_outer_repin(self):
        root = self.fixture_root()
        for mode in ('missing', 'duplicate', 'reordered', 'outside-path', 'wrong-status',
                     'before-sha', 'before-blob', 'after-sha', 'after-blob', 'hunk', 'extra-field'):
            changed = copy.deepcopy(SELECTION); rows = changed['static_repair_changes']
            if mode == 'missing': rows.pop()
            elif mode == 'duplicate': rows.append(copy.deepcopy(rows[0]))
            elif mode == 'reordered': rows.reverse()
            elif mode == 'outside-path': rows[0]['path'] = 'Core/Unreviewed.swift'
            elif mode == 'wrong-status': rows[0]['status'] = 'A'
            elif mode == 'extra-field': rows[0]['ignored'] = True
            elif mode == 'hunk': rows[0]['hunks'][0]['before'] += '\n'
            else: rows[0][mode.replace('-', '_') + ('256' if mode.endswith('sha') else '')] = '0' * (64 if mode.endswith('sha') else 40)
            pin = Creator65Contract.sha(runner.encode(changed).encode())
            with self.subTest(mode=mode), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaises(ValueError):
                runner.validate_selection(changed, root)
        for field in ('base_commit', 'base_tree', 'allowed_changes'):
            changed = copy.deepcopy(SELECTION)
            changed['historical_base'][field] = changed[field]
            pin = Creator65Contract.sha(runner.encode(changed).encode())
            with self.subTest(historical_field=field), mock.patch.object(runner, 'SELECTION_CONTRACT_SHA256', pin), self.assertRaisesRegex(ValueError, 'historical nineteen-path'):
                runner.validate_selection(changed, root)

    def test_every_payload_checks_real_bytes_sha_blob_and_regular_file(self):
        root = self.fixture_root()
        for row in SELECTION['static_repair_changes']:
            path = root / row['path']; original = path.read_bytes()
            path.write_bytes(original + b'\n')
            with self.subTest(path=row['path'], mode='changed'), self.assertRaisesRegex(ValueError, 'current static repair bytes'):
                runner.validate_static_repair(SELECTION, root)
            path.unlink()
            with self.subTest(path=row['path'], mode='missing'), self.assertRaises(ValueError):
                runner.validate_static_repair(SELECTION, root)
            other = path.with_name(path.name + '.witness'); other.write_bytes(original); path.symlink_to(other)
            with self.subTest(path=row['path'], mode='symlink'), self.assertRaises(ValueError):
                runner.validate_static_repair(SELECTION, root)
            path.unlink(); other.unlink(); path.write_bytes(original)
            for field in ('after_sha256', 'after_blob'):
                changed = copy.deepcopy(SELECTION)
                next(r for r in changed['static_repair_changes'] if r['path'] == row['path'])[field] = '0' * (64 if field.endswith('sha256') else 40)
                pin = Creator65Contract.sha(runner.encode(changed['static_repair_changes']).encode())
                with self.subTest(path=row['path'], field=field), mock.patch.object(runner, 'STATIC_REPAIR_CHANGES_SHA256', pin), self.assertRaisesRegex(ValueError, 'current static repair (bytes|blob)'):
                    runner.validate_static_repair(changed, root)
        self.assertEqual(len(runner.validate_static_repair(SELECTION, root)), 11)

    def test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors(self):
        root = self.fixture_root()
        for row in SELECTION['static_repair_changes']:
            raw = (root / row['path']).read_bytes()
            if row['status'] == 'A':
                for field, value in [('before_sha256', Creator65Contract.sha(b'')),
                                     ('before_blob', Creator65Contract.blob(b'')),
                                     ('hunks', [{'before': '', 'after': raw.decode()}])]:
                    changed = copy.deepcopy(SELECTION)
                    next(r for r in changed['static_repair_changes'] if r['path'] == row['path'])[field] = value
                    pin = Creator65Contract.sha(runner.encode(changed['static_repair_changes']).encode())
                    with self.subTest(field=field), mock.patch.object(runner, 'STATIC_REPAIR_CHANGES_SHA256', pin), self.assertRaisesRegex(ValueError, 'fabricated predecessor'):
                        runner.validate_static_repair(changed, root)
                continue
            for mode, mutant in [('off-hunk', raw + b'\n'),
                                 ('missing', raw.replace(row['hunks'][0]['after'].encode(), b'', 1)),
                                 ('duplicate', raw + row['hunks'][0]['after'].encode())]:
                forged = copy.deepcopy(row)
                forged['after_sha256'], forged['after_blob'] = Creator65Contract.sha(mutant), Creator65Contract.blob(mutant)
                with self.subTest(path=row['path'], mode=mode), self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged, mutant)

    def test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope(self):
        root = self.fixture_root()
        for mode in ('parent', 'merge', 'missing-base', 'tree', 'missing', 'extra', 'status', 'old-scope'):
            def transport(command, actual_root):
                result = scope_transport(command, actual_root)
                if command[1] == 'rev-list':
                    if mode == 'parent': return 'a' * 40 + ' ' + runner.HISTORICAL_BASE_COMMIT
                    if mode == 'merge': return result + ' ' + 'f' * 40
                if command[1:3] == ['rev-parse', runner.BASE_COMMIT + '^{tree}']:
                    if mode == 'missing-base': raise ValueError('Read command failed')
                    if mode == 'tree': return 'c' * 40
                if command[1] == 'diff' and command[3] == runner.BASE_COMMIT:
                    if mode == 'missing': return '\n'.join(result.splitlines()[:-1])
                    if mode == 'extra': return result + '\nM\tApp/AppSession.swift'
                    if mode == 'status': return result.replace('A\ttools/tests/test_readiness_contract_parse_cache.py', 'M\ttools/tests/test_readiness_contract_parse_cache.py')
                    if mode == 'old-scope': return '\n'.join(runner.HISTORICAL_ALLOWED_CHANGES)
                return result
            with self.subTest(mode=mode), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=transport), self.assertRaisesRegex(ValueError, '3393|fifteen exact'):
                runner.verify_scope(root, SELECTION)
        for field, value in [('base_commit', runner.HISTORICAL_BASE_COMMIT),
                             ('base_tree', runner.HISTORICAL_BASE_TREE),
                             ('historical_base_commit', runner.BASE_COMMIT),
                             ('historical_base_tree', runner.BASE_TREE)]:
            receipt, identity = ReceiptIdentity().receipt(); receipt[field] = value
            with self.subTest(receipt_field=field), self.assertRaises(ValueError):
                runner.validate_pass_receipt(receipt, identity, SELECTION)

    def test_each_baseline_and_current_tree_mode_blob_and_addition_absence(self):
        root = self.fixture_root()
        for before in (True, False):
            records = static_tree_records(root, before)
            def verify(rows):
                with mock.patch.object(runner, 'checked', return_value='\0'.join(rows) + '\0'):
                    return runner.verify_static_repair_tree(SELECTION, root, runner.BASE_TREE if before else 'a' * 40, before)
            self.assertEqual(len(verify(records)), 14 if before else 15)
            for i, record in enumerate(records):
                for mode in ('missing', 'duplicate', 'blob', 'executable', 'symlink', 'directory'):
                    changed = list(records)
                    if mode == 'missing': changed.pop(i)
                    elif mode == 'duplicate': changed.append(record)
                    elif mode == 'blob': changed[i] = '100644 blob ' + '0' * 40 + '\t' + record.split('\t')[1]
                    else: changed[i] = record.replace('100644 blob', {'executable':'100755 blob', 'symlink':'120000 blob', 'directory':'040000 tree'}[mode], 1)
                    with self.subTest(before=before, path=record.split('\t')[1], mode=mode), self.assertRaises(ValueError): verify(changed)
            extra = 'tools/tests/test_readiness_contract_parse_cache.py' if before else 'Core/Unreviewed.swift'
            with self.subTest(before=before, mode='unexpected-presence'), self.assertRaises(ValueError):
                verify(records + ['100644 blob ' + '1' * 40 + '\t' + extra])

    def test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs(self):
        root = self.fixture_root(); gitdir = root / 'static-witness.git'
        env = dict(os.environ, GIT_DIR=str(gitdir), GIT_INDEX_FILE=str(root / 'static-witness.index'))
        env.pop('GIT_OBJECT_DIRECTORY', None); env.pop('GIT_ALTERNATE_OBJECT_DIRECTORIES', None)
        subprocess.run(['git', 'init', '--bare', '-q', str(gitdir)], env=env, check=True)
        def git(*args, data=None):
            return subprocess.check_output(['git', *args], input=data, env=env).decode().strip()
        restored = runner.validate_static_repair(SELECTION, root)
        # The witness contains only real payload blobs. Diagnostic baseline objects
        # are fixed Git identities, not claimed source copies or a full 3393 tree.
        git('read-tree', '--empty')
        for path, raw in restored.items():
            oid = git('hash-object', '-w', '--stdin', data=raw)
            self.assertEqual(oid, self.BASELINES[path][2])
            git('update-index', '--add', '--cacheinfo', '100644', oid, path)
        # Existing diagnostic baseline identities need not be materialized to write
        # this explicit subset tree; allow-missing never changes production checks.
        for path, oid in runner.STATIC_DIAGNOSTIC_BASE_BLOBS.items():
            git('update-index', '--add', '--cacheinfo', '100644', oid, path)
        before = git('write-tree', '--missing-ok')
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(len(runner.verify_static_repair_tree(SELECTION, root, before, True)), 14)
        git('read-tree', '--empty')
        for change in runner.ALLOWED_CHANGES:
            path = change.split('\t', 1)[1]; raw = (root / path).read_bytes()
            oid = git('hash-object', '-w', '--stdin', data=raw)
            git('update-index', '--add', '--cacheinfo', '100644', oid, path)
        current = git('write-tree')
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(len(runner.verify_static_repair_tree(SELECTION, root, current, False)), 15)
        path = 'tools/tests/test_readiness_contract_parse_cache.py'
        oid = next(row['after_blob'] for row in SELECTION['static_repair_changes'] if row['path'] == path)
        git('update-index', '--cacheinfo', '100755', oid, path); mutant = git('write-tree')
        with mock.patch.dict(os.environ, env, clear=True), self.assertRaisesRegex(ValueError, 'mode/blob'):
            runner.verify_static_repair_tree(SELECTION, root, mutant, False)


class PublishedParentBridge(unittest.TestCase):
    def fixture_root(self):
        return Creator65Contract.fixture_root(self)

    def test_exact_eight_path_parent_bridge_preserves_old_source_domains(self):
        self.assertEqual(runner.CREATOR_COMMIT, 'b75f7549678caf51a65ec8942b6a6d0c23e887de')
        self.assertEqual(runner.CREATOR_TREE, '6d5a1e4a1486b3e97ed2f1e995ac5194e568bc20')
        expected = ('Questify.xcodeproj/project.pbxproj', 'Resources/Localizable.xcstrings',
                    'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
                    'Tests/ContractChecks/test_template_shelf_state_projection.py',
                    'tools/run138_editor_readiness.py', 'tools/run138_editor_readiness_contract.json',
                    'tools/tests/creator_shelf_state_history.py', 'tools/tests/test_creator_shelf_state_history.py')
        self.assertEqual(runner.CREATOR_PARENT_PATHS, expected)
        self.assertEqual(tuple(row['path'] for row in SELECTION['creator_parent_changes']), expected)
        self.assertEqual(Creator65Contract.sha(runner.encode(SELECTION['creator_parent_changes']).encode()),
                         runner.CREATOR_PARENT_CHANGES_SHA256)
        self.assertEqual({row['path'] for row in SELECTION['historical_source_files']}, runner.BOUND_SOURCES)
        self.assertEqual(len(SELECTION['historical_source_files']), 29)
        self.assertEqual({row['path'] for row in SELECTION['source_files']}, runner.BOUND_SOURCES)
        before = {row['path']:row['sha256'] for row in SELECTION['historical_source_files']}
        after = {row['path']:row['sha256'] for row in SELECTION['source_files']}
        self.assertEqual([p for p in before if before[p] != after[p]], ['Questify.xcodeproj/project.pbxproj'])
        self.assertEqual(len(runner.PARENT_HISTORY_CHANGES), 34)
        self.assertEqual(SELECTION['creator_base'], {'base_commit':runner.CREATOR_COMMIT,
                         'base_tree':runner.CREATOR_TREE,'parent_changes':list(runner.PARENT_HISTORY_CHANGES)})
        for row in SELECTION['creator_parent_changes']:
            self.assertEqual(row['status'], 'M')
            self.assertIn(row['path'], runner.BOUND_SOURCES | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS))

    def test_current_to_true_parent_to_b75_inverses_match_every_historical_source(self):
        root = self.fixture_root()
        parent = runner.validate_static_repair(SELECTION, root)
        historical = runner.restore_creator_inputs(SELECTION, root)
        self.assertEqual(set(historical), set(runner.CREATOR_PARENT_PATHS))
        for row in SELECTION['creator_parent_changes']:
            raw = parent.get(row['path'], (root / row['path']).read_bytes())
            with self.subTest(path=row['path']):
                self.assertEqual(Creator65Contract.sha(raw), row['after_sha256'])
                self.assertEqual(Creator65Contract.blob(raw), row['after_blob'])
                self.assertEqual(runner.inverse_reviewed_repair(row, raw), historical[row['path']])
                self.assertEqual(Creator65Contract.sha(historical[row['path']]), row['before_sha256'])
                self.assertEqual(Creator65Contract.blob(historical[row['path']]), row['before_blob'])
        for row in SELECTION['historical_source_files']:
            raw = historical.get(row['path'], (root / row['path']).read_bytes())
            self.assertEqual(Creator65Contract.sha(raw), row['sha256'])
        self.assertEqual(len(runner.validate_creator_changes(SELECTION, root)), 11)

    def test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs(self):
        root = self.fixture_root()
        for mode in ('missing','duplicate','reordered','outside','before-sha','before-blob',
                     'after-sha','after-blob','hunks','status','extra-field'):
            changed = copy.deepcopy(SELECTION); rows = changed['creator_parent_changes']
            if mode == 'missing': rows.pop()
            elif mode == 'duplicate': rows.append(copy.deepcopy(rows[0]))
            elif mode == 'reordered': rows.reverse()
            elif mode == 'outside': rows[0]['path'] = 'Core/Unreviewed.swift'
            elif mode == 'status': rows[0]['status'] = 'A'
            elif mode == 'extra-field': rows[0]['ignored'] = True
            elif mode == 'hunks': rows[0]['hunks'].pop()
            else: rows[0][mode.replace('-','_') + ('256' if mode.endswith('sha') else '')] = '0' * (64 if mode.endswith('sha') else 40)
            pin = Creator65Contract.sha(runner.encode(changed).encode())
            with self.subTest(mode=mode), mock.patch.object(runner,'SELECTION_CONTRACT_SHA256',pin), self.assertRaises(ValueError):
                runner.validate_selection(changed,root)
        changed = copy.deepcopy(SELECTION)
        next(r for r in changed['historical_source_files'] if r['path'] == 'Questify.xcodeproj/project.pbxproj')['sha256'] = next(r['sha256'] for r in changed['source_files'] if r['path'] == 'Questify.xcodeproj/project.pbxproj')
        with self.assertRaisesRegex(ValueError,'historical source bindings'):
            runner.restore_creator_inputs(changed,root)

    def test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources(self):
        root = self.fixture_root(); parent = runner.validate_static_repair(SELECTION,root)
        for row in SELECTION['creator_parent_changes']:
            path = root / row['path']; current = path.read_bytes()
            path.write_bytes(current + b'\n')
            with self.subTest(path=row['path'],mode='current'),self.assertRaises(ValueError):
                runner.restore_creator_inputs(SELECTION,root)
            path.write_bytes(current)
            raw = parent.get(row['path'], current)
            for mode,mutant in [('off-hunk',raw+b'\n'),('missing',raw.replace(row['hunks'][0]['after'].encode(),b'',1)),('duplicate',raw+row['hunks'][0]['after'].encode())]:
                forged = copy.deepcopy(row); forged['after_sha256'],forged['after_blob'] = Creator65Contract.sha(mutant),Creator65Contract.blob(mutant)
                with self.subTest(path=row['path'],mode=mode),self.assertRaises(ValueError):
                    runner.inverse_reviewed_repair(forged,mutant)
        self.assertEqual(len(runner.restore_creator_inputs(SELECTION,root)),8)

    def test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact(self):
        for before in (True,False):
            records = ['100644 blob '+r['before_blob' if before else 'after_blob']+'\t'+r['path'] for r in SELECTION['creator_parent_changes']]
            def verify(rows):
                with mock.patch.object(runner,'checked',return_value='\0'.join(rows)+'\0'):
                    return runner.verify_creator_parent_tree(SELECTION,SOURCE,runner.CREATOR_TREE if before else runner.BASE_TREE,before)
            self.assertEqual(len(verify(records)),8)
            for i,record in enumerate(records):
                for mode in ('missing','duplicate','blob','mode','symlink','tree'):
                    changed = list(records)
                    if mode == 'missing':changed.pop(i)
                    elif mode == 'duplicate':changed.append(record)
                    elif mode == 'blob':changed[i]='100644 blob '+'0'*40+'\t'+record.split('\t')[1]
                    else:changed[i]=record.replace('100644 blob',{'mode':'100755 blob','symlink':'120000 blob','tree':'040000 tree'}[mode],1)
                    with self.subTest(before=before,path=record.split('\t')[1],mode=mode),self.assertRaises(ValueError):verify(changed)
            with self.assertRaises(ValueError):verify(records+['100644 blob '+'0'*40+'\tCore/Unreviewed.swift'])

    def test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent(self):
        for mode in ('missing','extra','old-nineteen'):
            def transport(command,root):
                result=scope_transport(command,root)
                if command[1]=='diff' and command[3]==runner.CREATOR_COMMIT:
                    if mode=='missing':return '\n'.join(result.splitlines()[:-1])
                    if mode=='extra':return result+'\nM\tCore/Unreviewed.swift'
                    return '\n'.join(runner.HISTORICAL_ALLOWED_CHANGES)
                return result
            with self.subTest(mode=mode),mock.patch.dict(os.environ,{'GITHUB_SHA':'a'*40}),mock.patch.object(runner,'checked',side_effect=transport),self.assertRaisesRegex(ValueError,'creator-to-3393 history'):
                runner.verify_scope(SOURCE,SELECTION)
        for field,value in [('base_commit',runner.CREATOR_COMMIT),('base_tree',runner.CREATOR_TREE),('creator_base_commit',runner.BASE_COMMIT),('creator_base_tree',runner.BASE_TREE)]:
            receipt,identity=ReceiptIdentity().receipt();receipt[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):runner.validate_pass_receipt(receipt,identity,SELECTION)


class FixedPublicCreatorRead(unittest.TestCase):
    @staticmethod
    def headers(tree=None,parent=None):
        return 'tree '+(tree or runner.CREATOR_TREE)+'\nparent '+(parent or runner.HISTORICAL_BASE_COMMIT)+'\nauthor Test <test@example.invalid> 1 +0000\n\nSynthetic commit metadata'

    def present(self,command,root):
        if command[1:3]==['cat-file','-e']:return ''
        if command==['git','cat-file','-p',runner.CREATOR_COMMIT]:return self.headers()
        raise AssertionError(command)

    def missing(self,command,root):
        if command[1:3]==['cat-file','-e']:raise ValueError('Synthetic missing object')
        return self.present(command,root)

    def test_present_exact_object_never_fetches_or_inspects_network_configuration(self):
        with mock.patch.object(runner,'checked',side_effect=self.present) as read,mock.patch.object(runner,'execute') as execute:
            runner.ensure_creator_commit(SOURCE)
            execute.assert_not_called()
            self.assertEqual(read.call_args_list,[mock.call(['git','cat-file','-e',runner.CREATOR_COMMIT+'^{commit}'],SOURCE),mock.call(['git','cat-file','-e',runner.CREATOR_COMMIT+'^{tree}'],SOURCE),mock.call(['git','cat-file','-p',runner.CREATOR_COMMIT],SOURCE)])

    def test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read(self):
        inherited={'GITHUB_TOKEN':'do-not-forward','GH_TOKEN':'do-not-forward','SECRET':'do-not-forward',
                   'HTTPS_PROXY':'https://do-not-forward.invalid','GIT_CONFIG_COUNT':'1','GIT_ASKPASS':'do-not-forward',
                   'SSH_AUTH_SOCK':'do-not-forward','HOME':'do-not-forward','GIT_OBJECT_DIRECTORY':'do-not-forward'}
        with mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',side_effect=[(0,b'core.repositoryformatversion\ncore.bare\n'),(0,b'')]) as execute,mock.patch.dict(os.environ,inherited):
            runner.ensure_creator_commit(SOURCE)
        self.assertEqual(execute.call_count,2)
        config,fetch=execute.call_args_list
        self.assertEqual(config.args,(['git','config','--local','--includes','--name-only','--list'],SOURCE,10,True))
        command=fetch.args[0]
        self.assertEqual(fetch.args[1:],(SOURCE,60,True))
        self.assertEqual(command[-7:],['fetch','--no-tags','--no-write-fetch-head','--depth=1','--no-recurse-submodules','https://github.com/liboyang42-cpu/chengyin-ios.git','b75f7549678caf51a65ec8942b6a6d0c23e887de'])
        for value in ('credential.helper=','core.askPass=','http.extraHeader=','http.followRedirects=false','protocol.allow=never','protocol.https.allow=always'):self.assertIn(value,command)
        environment=fetch.kwargs['env']
        self.assertEqual(set(environment),{'PATH','LANG','HOME','GIT_TERMINAL_PROMPT','GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_ASKPASS','SSH_ASKPASS'})
        self.assertNotIn('do-not-forward',environment.values())
        self.assertEqual(environment['GIT_TERMINAL_PROMPT'],'0')
        self.assertEqual(environment['GIT_CONFIG_NOSYSTEM'],'1')
        self.assertEqual(environment['GIT_CONFIG_GLOBAL'],'/dev/null')
        self.assertEqual(environment['HOME'],'/dev/null')
        self.assertEqual(config.kwargs['env'],environment)
        for action in ('checkout','reset','push','pull'):self.assertNotIn(action,command)

    def test_offline_timeout_or_unreadable_config_fail_closed_without_retry(self):
        for mode in ('offline','timeout','config'):
            outputs=[(1,b'')] if mode=='config' else [(0,b'core.bare\n'),(124 if mode=='timeout' else 1,b'')]
            with self.subTest(mode=mode),mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',side_effect=outputs) as execute,self.assertRaises(ValueError):
                runner.ensure_creator_commit(SOURCE)
            self.assertEqual(execute.call_count,1 if mode=='config' else 2)

    def test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected(self):
        for existing in (True,False):
            for mode in ('tree','parent','merge'):
                headers=self.headers(tree='0'*40) if mode=='tree' else self.headers(parent=runner.BASE_COMMIT) if mode=='parent' else self.headers().replace('\nauthor','\nparent '+'1'*40+'\nauthor')
                def read(command,root):
                    if command[1:3]==['cat-file','-e']:
                        if existing:return ''
                        raise ValueError('Synthetic missing object')
                    return headers
                with self.subTest(existing=existing,mode=mode),mock.patch.object(runner,'checked',side_effect=read),mock.patch.object(runner,'execute',side_effect=[(0,b'core.bare\n'),(0,b'')]) as execute,self.assertRaisesRegex(ValueError,'commit/tree/parent identity'):
                    runner.ensure_creator_commit(SOURCE)
                self.assertEqual(execute.call_count,0 if existing else 2)

    def test_credential_redirect_include_and_auth_configuration_never_reach_fetch(self):
        for key in ('credential.helper','credential.https://github.com.username','http.extraheader','http.https://github.com/.extraheader','http.proxy','url.ssh://example.invalid.insteadof','include.path','includeif.gitdir:work.path','core.askpass','extensions.worktreeconfig'):
            with self.subTest(key=key),mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',return_value=(0,(key+'\n').encode())) as execute,self.assertRaisesRegex(ValueError,'rejects credential, redirect, or included'):
                runner.ensure_creator_commit(SOURCE)
            self.assertEqual(execute.call_count,1)

    def test_public_target_cannot_be_generalized_by_changing_fixed_identity(self):
        for key in ('CREATOR_COMMIT','CREATOR_TREE','HISTORICAL_BASE_COMMIT'):
            with self.subTest(key=key),mock.patch.object(runner,key,'f'*40),mock.patch.object(runner,'checked') as read,mock.patch.object(runner,'execute') as execute,self.assertRaisesRegex(ValueError,'fixed public creator object target'):
                runner.ensure_creator_commit(SOURCE)
            read.assert_not_called();execute.assert_not_called()


ORIGINAL83_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity')
ORIGINAL83_SOURCE_SHA256 = 'dba749c01625197f25d498342708d4e03f9c7fe10c48416b4099bda4863d2c84'



def original83_source_blocks(raw):
    """Retain every original byte from decorators through each complete method."""
    tree = ast.parse(raw.decode('utf-8'))
    lines = raw.splitlines(keepends=True)
    found = {}
    for cls in tree.body:
        if not isinstance(cls, ast.ClassDef): continue
        for node in cls.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
            identity = cls.name + '.' + node.name
            if identity not in ORIGINAL83_IDENTITIES: continue
            if identity in found: raise ValueError('Duplicate original method identity')
            first = min([node.lineno] + [d.lineno for d in node.decorator_list])
            found[identity] = b''.join(lines[first - 1:node.end_lineno]).decode('utf-8')
    if len(found) != 83 or set(found) != set(ORIGINAL83_IDENTITIES):
        raise ValueError('Missing original83 complete source identity')
    return found


def verify_original83_source(raw):
    found = original83_source_blocks(raw)
    if runner.hashlib.sha256(runner.encode(found).encode()).hexdigest() != ORIGINAL83_SOURCE_SHA256:
        raise ValueError('Changed complete original83 method source bytes')
    return found


class NativeC2afBoundary(unittest.TestCase):
    def fixture_root(self):
        temporary = tempfile.TemporaryDirectory(prefix='targeted-native14-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for relative in runner.NATIVE_PATHS:
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(runner.portable_f04_source(relative, (CURRENT_SOURCE / relative).read_bytes()))
        return root

    def rows_pin(self, selection):
        return runner.hashlib.sha256(runner.encode(selection['native_repair']['payload_changes']).encode()).hexdigest()

    def test_original83_complete_method_sources_are_unchanged(self):
        raw = (CURRENT_TOOLS / 'tests/test_targeted_native.py').read_bytes()
        self.assertEqual(len(verify_original83_source(raw)), 83)

    def test_new14_old15_history34_history19_and_original65_remain_separate(self):
        self.assertEqual(runner.NATIVE_BASE_COMMIT, 'c2af90a5e11a789ca8dc99eb8daae2c1e84e0700')
        self.assertEqual(runner.NATIVE_BASE_TREE, 'bb341123236a28027becc55e06f35cb294bb718f')
        expected = {'App/ProjectEditIssueNavigation.swift', 'tools/run138_editor_readiness_contract.json',
                    'tools/run138_editor_readiness.py', 'Tests/ContractChecks/test_category_roam_registration.py',
                    'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
                    'Tests/ContractChecks/test_global_search_category_recovery.py',
                    'tools/club_customer_directory_admission.py', 'tools/tests/test_readiness_contract_parse_cache.py',
                    'tools/tests/test_run138_current_ci_entry.py', 'tools/run_targeted_native.py',
                    'tools/targeted_native_selection.json', 'tools/tests/test_targeted_native.py',
                    'Questify.xcodeproj/project.pbxproj', 'tools/run138_current_source_projection.py'}
        self.assertEqual(set(runner.NATIVE_PATHS), expected)
        self.assertEqual(len(runner.NATIVE_PATHS), 14)
        self.assertEqual(len(runner.NATIVE_PAYLOAD_PATHS), 11)
        self.assertEqual(set(runner.NATIVE_ALLOWED_CHANGES), {'M\t' + p for p in expected})
        self.assertEqual([len(runner.ALLOWED_CHANGES), len(runner.PARENT_HISTORY_CHANGES),
                          len(runner.HISTORICAL_ALLOWED_CHANGES)], [15, 34, 19])
        self.assertEqual(runner.native_predecessor_selection(CURRENT_SELECTION), SELECTION)
        raw = runner.native_predecessor_selection_bytes(CURRENT_SELECTION)
        self.assertEqual(runner.hashlib.sha256(raw).hexdigest(),
                         'c3562224a372d442434ed28bc861aef370cf18e72d69faf9b97b0a8652247bf5')
        self.assertEqual(runner.blob_id(raw), '02ae2c0e2092a40257ecf8e9aca83f5776470853')
        reordered = dict(reversed(list(CURRENT_SELECTION.items())))
        with self.assertRaisesRegex(ValueError, 'selection encoding'):
            runner.native_predecessor_selection_bytes(reordered)
        self.assertEqual(CURRENT_SELECTION['groups'], SELECTION['groups'])
        self.assertEqual(runner.validate_native_selection(CURRENT_SELECTION, CURRENT_SOURCE), CURRENT_SELECTION)

    def test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources(self):
        restored = runner.native_predecessor_sources(CURRENT_SELECTION, CURRENT_SOURCE)
        self.assertEqual(set(restored), set(runner.NATIVE_PAYLOAD_PATHS))
        for relative, raw in restored.items():
            self.assertEqual((runner.hashlib.sha256(raw).hexdigest(), runner.blob_id(raw)),
                             runner.NATIVE_PREIMAGES[relative])
        self.assertEqual(runner.hashlib.sha256(restored['tools/run138_editor_readiness_contract.json']).hexdigest(),
                         'd3fedafc9efe917220f4c52cb4c82d742f840a7307546da35e4da130a80d7fdb')
        self.assertEqual(runner.validate_static_repair(SELECTION, CURRENT_SOURCE, predecessor=restored),
                         runner.validate_static_repair(SELECTION, SOURCE))
        self.assertEqual(runner.validate_reviewed_repairs(SELECTION, CURRENT_SOURCE, predecessor=restored),
                         runner.validate_reviewed_repairs(SELECTION, SOURCE))

    def test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted(self):
        for mode in ('missing', 'extra-field', 'missing-row', 'duplicate', 'reorder', 'unknown-path',
                     'old-parent', 'wrong-tree', 'status', 'diagnostic'):
            changed = copy.deepcopy(CURRENT_SELECTION)
            layer = changed['native_repair']
            if mode == 'missing': del changed['native_repair']
            elif mode == 'extra-field': layer['unknown'] = True
            elif mode == 'missing-row': layer['payload_changes'].pop()
            elif mode == 'duplicate': layer['payload_changes'].append(copy.deepcopy(layer['payload_changes'][0]))
            elif mode == 'reorder': layer['payload_changes'].reverse()
            elif mode == 'unknown-path': layer['payload_changes'][0]['path'] = 'Core/Unreviewed.swift'
            elif mode == 'old-parent': layer['base_commit'] = runner.BASE_COMMIT
            elif mode == 'wrong-tree': layer['base_tree'] = '0' * 40
            elif mode == 'status': layer['allowed_changes'][0] = 'A\t' + runner.NATIVE_PATHS[0]
            else: layer['diagnostic_before_blobs']['tools/run_targeted_native.py'] = '0' * 40
            pin = runner.hashlib.sha256(runner.encode(changed).encode()).hexdigest()
            with self.subTest(mode=mode), mock.patch.object(runner, 'NATIVE_SELECTION_CONTRACT_SHA256', pin), self.assertRaises(ValueError):
                runner.validate_native_selection(changed, CURRENT_SOURCE)

    def test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape(self):
        for field in ('before_sha256', 'before_blob', 'after_sha256', 'after_blob', 'status', 'hunks', 'unknown'):
            changed = copy.deepcopy(CURRENT_SELECTION)
            row = changed['native_repair']['payload_changes'][0]
            if field.endswith('sha256'): row[field] = '0' * 64
            elif field.endswith('blob'): row[field] = '0' * 40
            elif field == 'status': row[field] = 'A'
            elif field == 'hunks': row[field] = [{'before': '', 'after': 'forged'}]
            else: row[field] = True
            with self.subTest(field=field), mock.patch.object(runner, 'NATIVE_REPAIR_CHANGES_SHA256', self.rows_pin(changed)), self.assertRaises(ValueError):
                runner.native_predecessor_sources(changed, CURRENT_SOURCE)

    def test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation(self):
        root = self.fixture_root()
        originals = {p: (root / p).read_bytes() for p in runner.NATIVE_PAYLOAD_PATHS}
        for relative, raw in originals.items():
            path = root / relative
            for mode in ('missing', 'symlink', 'newline', 'same-stat', 'historical'):
                old_stat = path.stat()
                path.unlink()
                if mode == 'symlink': path.symlink_to(CURRENT_SOURCE / relative)
                elif mode == 'newline': path.write_bytes(raw + b'\n')
                elif mode == 'same-stat':
                    path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
                    os.utime(path, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))
                elif mode == 'historical': path.write_bytes(runner.native_predecessor_sources(CURRENT_SELECTION, CURRENT_SOURCE)[relative])
                with self.subTest(path=relative, mode=mode), self.assertRaises((ValueError, FileNotFoundError)):
                    runner.native_predecessor_sources(CURRENT_SELECTION, root)
                if path.is_symlink() or path.exists(): path.unlink()
                path.write_bytes(raw)
        runner.native_predecessor_sources(CURRENT_SELECTION, root)
        (root / runner.NATIVE_PATHS[0]).unlink()
        with self.assertRaises((ValueError, FileNotFoundError)):
            runner.native_predecessor_sources(CURRENT_SELECTION, root)

    def test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse(self):
        root = self.fixture_root(); relative = runner.NATIVE_PATHS[0]; path = root / relative
        raw = path.read_bytes()
        for mutant in (raw.replace(b'\n', b'\r\n'), raw.replace(b'\n', b'\r'), raw + b'// off-hunk\n'):
            path.write_bytes(mutant)
            changed = copy.deepcopy(CURRENT_SELECTION); row = changed['native_repair']['payload_changes'][0]
            row['after_sha256'] = runner.hashlib.sha256(mutant).hexdigest(); row['after_blob'] = runner.blob_id(mutant)
            with mock.patch.object(runner, 'NATIVE_REPAIR_CHANGES_SHA256', self.rows_pin(changed)), self.assertRaises(ValueError):
                runner.native_predecessor_sources(changed, root)

    def test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks(self):
        restored = runner.native_predecessor_sources(CURRENT_SELECTION, CURRENT_SOURCE)
        for mode in ('missing', 'extra', 'changed'):
            changed = dict(restored)
            if mode == 'missing': changed.pop(runner.NATIVE_PATHS[0])
            elif mode == 'extra': changed['Core/Unreviewed.swift'] = b'x'
            else: changed['tools/run138_editor_readiness.py'] += b'\n'
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                runner.validate_selection(SELECTION, CURRENT_SOURCE, predecessor=changed)

    def test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks(self):
        receipt, identity = ReceiptIdentity().receipt()
        with self.assertRaises(ValueError): runner.validate_native_pass_receipt(receipt, identity, CURRENT_SELECTION)
        receipt.update(native_base_commit=runner.NATIVE_BASE_COMMIT, native_base_tree=runner.NATIVE_BASE_TREE,
                       native_selection=runner.NATIVE_NAME)
        runner.validate_native_pass_receipt(receipt, identity, CURRENT_SELECTION)
        for field in ('native_base_commit', 'native_base_tree', 'native_selection'):
            mutant = copy.deepcopy(receipt); mutant[field] = 'wrong'
            with self.subTest(field=field), self.assertRaises(ValueError):
                runner.validate_native_pass_receipt(mutant, identity, CURRENT_SELECTION)
        receipt['groups']['core']['actual'].pop()
        with self.assertRaises(ValueError): runner.validate_native_pass_receipt(receipt, identity, CURRENT_SELECTION)

    def tree_records(self, root, before):
        rows = ['100644 blob ' + row['before_blob' if before else 'after_blob'] + '\t' + row['path']
                for row in CURRENT_SELECTION['native_repair']['payload_changes']]
        rows.extend('100644 blob ' + (old if before else runner.blob_id((root / relative).read_bytes()))
                    + '\t' + relative for relative, old in runner.NATIVE_DIAGNOSTIC_BASE_BLOBS.items())
        return rows

    def test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory(self):
        for before in (True, False):
            correct = self.tree_records(CURRENT_SOURCE, before)
            with mock.patch.object(runner, 'checked', return_value='\0'.join(correct) + '\0'):
                self.assertEqual(len(runner.verify_native_tree(CURRENT_SELECTION, CURRENT_SOURCE, 'synthetic', before)), 14)
            for index in range(len(correct)):
                for mode in ('missing', 'blob', 'mode', 'type', 'duplicate'):
                    mutant = list(correct)
                    if mode == 'missing': mutant.pop(index)
                    elif mode == 'blob': mutant[index] = re.sub('[0-9a-f]{40}', '0' * 40, mutant[index], count=1)
                    elif mode == 'mode': mutant[index] = mutant[index].replace('100644', '100755', 1)
                    elif mode == 'type': mutant[index] = mutant[index].replace(' blob ', ' commit ', 1)
                    else: mutant.append(mutant[index])
                    with self.subTest(before=before, index=index, mode=mode), mock.patch.object(runner, 'checked', return_value='\0'.join(mutant) + '\0'), self.assertRaises(ValueError):
                        runner.verify_native_tree(CURRENT_SELECTION, CURRENT_SOURCE, 'synthetic', before)

    def native_transport(self, command, root):
        if command[1:3] == ['rev-parse', runner.NATIVE_BASE_COMMIT + '^{tree}']: return runner.NATIVE_BASE_TREE
        if command[1:3] == ['cat-file', '-p']:
            target = command[3]
            if target == 'a' * 40: return 'tree ' + 'b' * 40 + '\nparent ' + runner.NATIVE_BASE_COMMIT + '\n\nCurrent witness'
            if target == runner.NATIVE_BASE_COMMIT: return 'tree ' + runner.NATIVE_BASE_TREE + '\nparent ' + runner.BASE_COMMIT + '\n\nPublished c2af witness'
            if target == runner.BASE_COMMIT: return FixedPublicRepairRead.headers()
        if command[1] == 'diff':
            if command[3] == runner.NATIVE_BASE_COMMIT: return '\n'.join(runner.NATIVE_ALLOWED_CHANGES)
        if command[1] == 'ls-tree':
            if tuple(command[5:]) == runner.NATIVE_PATHS:
                return '\0'.join(self.tree_records(root, command[3] == runner.NATIVE_BASE_TREE)) + '\0'
            if command[3] == runner.NATIVE_BASE_TREE:
                rows = ['100644 blob ' + row['after_blob'] + '\t' + row['path'] for row in SELECTION['static_repair_changes']]
                rows.extend('100644 blob ' + blob + '\t' + path for path, blob in runner.NATIVE_DIAGNOSTIC_BASE_BLOBS.items())
                return '\0'.join(rows) + '\0'
        return scope_transport(command, root)

    def test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer(self):
        with mock.patch.object(runner, 'checked', side_effect=self.native_transport), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}):
            identity = runner.verify_native_scope(CURRENT_SOURCE, CURRENT_SELECTION)
            self.assertEqual(identity['native_base_commit'], runner.NATIVE_BASE_COMMIT)
            self.assertEqual(identity['base_commit'], runner.BASE_COMMIT)
        for mode in ('parent', 'merge', 'missing-parent', 'base-tree', 'old15', 'missing-path', 'extra-path',
                     'status', 'c2af-parent', 'c2af-tree', 'prior15', 'history34', 'history19', 'dirty'):
            def transport(command, root):
                result = self.native_transport(command, root)
                if command[1:4] == ['cat-file', '-p', 'a' * 40]:
                    if mode == 'parent': return result.replace(runner.NATIVE_BASE_COMMIT, runner.BASE_COMMIT)
                    if mode == 'merge': return result.replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n')
                    if mode == 'missing-parent': raise ValueError('Unavailable parent')
                if command[1:3] == ['rev-parse', runner.NATIVE_BASE_COMMIT + '^{tree}'] and mode == 'base-tree': return '0' * 40
                if command[1:4] == ['cat-file', '-p', runner.NATIVE_BASE_COMMIT]:
                    if mode == 'c2af-parent': return result.replace(runner.BASE_COMMIT, runner.CREATOR_COMMIT)
                    if mode == 'c2af-tree': return result.replace(runner.NATIVE_BASE_TREE, '0' * 40)
                if command[1] == 'diff':
                    if command[3] == runner.NATIVE_BASE_COMMIT:
                        if mode == 'old15': return '\n'.join(runner.ALLOWED_CHANGES)
                        if mode == 'missing-path': return '\n'.join(result.splitlines()[:-1])
                        if mode == 'extra-path': return result + '\nM\tCore/Unreviewed.swift'
                        if mode == 'status': return result.replace('M\t', 'A\t', 1)
                    if (mode, command[3]) in [('prior15', runner.BASE_COMMIT), ('history34', runner.CREATOR_COMMIT), ('history19', runner.HISTORICAL_BASE_COMMIT)]: return ''
                if command[1] == 'status' and mode == 'dirty': return ' M Core/Changed.swift'
                return result
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=transport), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), self.assertRaises(ValueError):
                runner.verify_native_scope(CURRENT_SOURCE, CURRENT_SELECTION)

    def test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport(self):
        root = self.fixture_root(); gitdir = root / 'witness.git'
        environment = dict(os.environ, GIT_DIR=str(gitdir), GIT_INDEX_FILE=str(root / 'witness.index'))
        for key in ('GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES'): environment.pop(key, None)
        subprocess.run(['git', 'init', '--bare', '-q', str(gitdir)], env=environment, check=True)
        (root / '.git').write_text('gitdir: ' + str(gitdir) + '\n')
        def git(*args, data=None):
            return subprocess.check_output(['git', *args], input=data, env=environment).decode().strip()
        git('read-tree', '--empty')
        for relative in runner.NATIVE_PATHS:
            oid = git('hash-object', '-w', '--stdin', data=(root / relative).read_bytes())
            git('update-index', '--add', '--cacheinfo', '100644', oid, relative)
        witness = git('write-tree')
        # This disposable exact14 subset is not a claim to recreate the full c2af
        # or a real new HEAD. Published full-object witness is a separate gate.
        with mock.patch.dict(os.environ, environment, clear=True):
            self.assertEqual(len(runner.verify_native_tree(CURRENT_SELECTION, root, witness, False)), 14)
        for relative in runner.NATIVE_PATHS:
            git('read-tree', witness)
            git('update-index', '--cacheinfo', '100755', runner.blob_id((root / relative).read_bytes()), relative)
            mutant = git('write-tree')
            with self.subTest(path=relative), mock.patch.dict(os.environ, environment, clear=True), self.assertRaises(ValueError):
                runner.verify_native_tree(CURRENT_SELECTION, root, mutant, False)


class FixedPublicRepairRead(unittest.TestCase):
    @staticmethod
    def headers(tree=None, parent=None):
        return 'tree ' + (tree or runner.BASE_TREE) + '\nparent ' + (parent or 'cf7b3e7f0f7c2105b23c439f2314d6163886c126') + '\n\nSynthetic 3393 metadata'

    def present(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        if command == ['git', 'cat-file', '-p', runner.BASE_COMMIT]: return self.headers()
        raise AssertionError(command)

    def missing(self, command, root):
        if command[1:3] == ['cat-file', '-e']: raise ValueError('Synthetic unavailable 3393 object')
        return self.present(command, root)

    def test_present_exact_3393_never_fetches(self):
        with mock.patch.object(runner, 'checked', side_effect=self.present), mock.patch.object(runner, 'execute') as execute:
            runner.ensure_repair_commit(CURRENT_SOURCE)
            execute.assert_not_called()

    def test_missing_3393_uses_only_separate_fixed_public_bounded_fetch(self):
        inherited = {'GITHUB_TOKEN': 'not-forwarded', 'GIT_CONFIG_COUNT': '1', 'HTTPS_PROXY': 'not-forwarded',
                     'HOME': 'not-forwarded', 'GIT_OBJECT_DIRECTORY': 'not-forwarded', 'SSH_AUTH_SOCK': 'not-forwarded'}
        with mock.patch.object(runner, 'checked', side_effect=self.missing), mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute, mock.patch.dict(os.environ, inherited):
            runner.ensure_repair_commit(CURRENT_SOURCE)
        self.assertEqual(execute.call_count, 2)
        config, fetch = execute.call_args_list
        self.assertEqual(config.args, (['git', 'config', '--local', '--includes', '--name-only', '--list'], CURRENT_SOURCE, 10, True))
        self.assertEqual(fetch.args[1:], (CURRENT_SOURCE, 60, True))
        self.assertEqual(fetch.args[0][-7:], ['fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                                           'https://github.com/liboyang42-cpu/chengyin-ios.git', '3393ec85076a7a4e246e94e98ddf81f6b73ede2f'])
        for flag in ('credential.helper=', 'core.askPass=', 'http.extraHeader=', 'http.followRedirects=false', 'protocol.allow=never', 'protocol.https.allow=always'):
            self.assertIn(flag, fetch.args[0])
        environment = fetch.kwargs['env']
        self.assertEqual(set(environment), {'PATH', 'LANG', 'HOME', 'GIT_TERMINAL_PROMPT', 'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_ASKPASS', 'SSH_ASKPASS'})
        self.assertEqual(config.kwargs['env'], environment)
        self.assertNotIn('not-forwarded', environment.values())
        self.assertEqual(environment['HOME'], '/dev/null')
        self.assertEqual(environment['GIT_TERMINAL_PROMPT'], '0')
        self.assertEqual(environment['GIT_CONFIG_GLOBAL'], '/dev/null')

    def test_3393_network_failures_and_credential_configuration_refuse_without_retry(self):
        for key in ('credential.helper', 'http.extraheader', 'http.proxy', 'url.other.insteadof',
                    'include.path', 'includeif.gitdir:x.path', 'core.askpass', 'extensions.worktreeconfig'):
            with self.subTest(key=key), mock.patch.object(runner, 'checked', side_effect=self.missing), mock.patch.object(runner, 'execute', return_value=(0, (key + '\n').encode())) as execute, self.assertRaises(ValueError):
                runner.ensure_repair_commit(CURRENT_SOURCE)
            self.assertEqual(execute.call_count, 1)
        for outputs in ([(1, b'')], [(0, b'core.bare\n'), (1, b'')], [(0, b'core.bare\n'), (124, b'')]):
            with mock.patch.object(runner, 'checked', side_effect=self.missing), mock.patch.object(runner, 'execute', side_effect=outputs) as execute, self.assertRaises(ValueError):
                runner.ensure_repair_commit(CURRENT_SOURCE)
            self.assertEqual(execute.call_count, len(outputs))

    def test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail(self):
        for field in ('BASE_COMMIT', 'BASE_TREE'):
            with mock.patch.object(runner, field, 'f' * 40), mock.patch.object(runner, 'checked') as checked, mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_repair_commit(CURRENT_SOURCE)
            checked.assert_not_called(); execute.assert_not_called()
        for existing in (True, False):
            for headers in (self.headers(tree='0' * 40), self.headers(parent=runner.CREATOR_COMMIT),
                            self.headers().replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n'), ''):
                def read(command, root):
                    if command[1:3] == ['cat-file', '-e']:
                        if existing: return ''
                        raise ValueError('Missing object')
                    return headers
                with mock.patch.object(runner, 'checked', side_effect=read), mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]), self.assertRaises(ValueError):
                    runner.ensure_repair_commit(CURRENT_SOURCE)


class PortableDiagnosticBoundary(unittest.TestCase):
    def test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings(self):
        raw = (CURRENT_TOOLS / 'tests/test_targeted_native.py').read_bytes()
        found = verify_original83_source(raw)
        segment = next(value for value in found.values() if 'self.assert' in value).encode()
        mutants = [raw.replace(segment, segment.replace(b'self.assert', b'self.asserX', 1), 1),
                   raw.replace(segment, b'    @unittest.skip("mutated")\n' + segment, 1),
                   raw.replace(segment, segment.replace(b'\n', b' # changed\n', 1), 1),
                   raw.replace(segment, b'', 1), raw.replace(segment, segment + b'\n' + segment, 1),
                   raw.replace(b'\n', b'\r\n'), raw.replace(b'\n', b'\r')]
        for mutant in mutants:
            with self.assertRaises((ValueError, SyntaxError)): verify_original83_source(mutant)

    def test_exact_f04_selection_source_and_four_path_layer_are_mandatory(self):
        self.assertEqual(runner.portable_predecessor_selection(PORTABLE_SELECTION), CURRENT_SELECTION)
        self.assertEqual(runner.PORTABLE_BASE_COMMIT, 'f04f1cab7ef92afcafcdbde411dde71b4a605820')
        self.assertEqual(runner.PORTABLE_BASE_TREE, '75569d4e6d8ed5c23ee9865164a8d01c2e346116')
        self.assertEqual(tuple(runner.PORTABLE_PATHS), ('tools/run_targeted_native.py',
                         'tools/targeted_native_selection.json', 'tools/tests/test_targeted_native.py',
                         'tools/tests/test_run138_current_ci_entry.py'))
        for mode in ('missing', 'extra', 'wrong-base', 'extra-path', 'old-method', 'key-order'):
            changed = copy.deepcopy(PORTABLE_SELECTION)
            if mode == 'missing': changed.pop('portable_diagnostics')
            elif mode == 'extra': changed['unknown'] = True
            elif mode == 'wrong-base': changed['portable_diagnostics']['base_commit'] = runner.NATIVE_BASE_COMMIT
            elif mode == 'extra-path': changed['portable_diagnostics']['allowed_changes'].append('M\tApp/Unexpected.swift')
            elif mode == 'old-method': changed['groups'][0]['methods'][0] += 'Changed'
            else: changed = dict(reversed(list(changed.items())))
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                runner.portable_predecessor_selection(changed)

    def test_all_four_actual_current_files_and_both_tree_authorities_are_strict(self):
        runner.validate_portable_selection(PORTABLE_SELECTION, CURRENT_SOURCE)
        with tempfile.TemporaryDirectory(prefix='portable-three-control-') as directory:
            root = Path(directory)
            for relative in runner.PORTABLE_PATHS:
                target = root / relative; target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((CURRENT_SOURCE / relative).read_bytes())
            for relative in runner.PORTABLE_PATHS:
                target = root / relative; raw = target.read_bytes(); stamp = target.stat()
                target.write_bytes(bytes([raw[0] ^ 1]) + raw[1:]); os.utime(target, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
                with self.assertRaises(ValueError): runner.validate_portable_selection(PORTABLE_SELECTION, root)
                target.unlink()
                with self.assertRaises(ValueError): runner.validate_portable_selection(PORTABLE_SELECTION, root)
                target.symlink_to(CURRENT_SOURCE / relative)
                with self.assertRaises(ValueError): runner.validate_portable_selection(PORTABLE_SELECTION, root)
                target.unlink(); target.write_bytes(raw)
        for before in (True, False):
            blobs = runner.PORTABLE_BEFORE_BLOBS if before else {p:runner.blob_id((CURRENT_SOURCE/p).read_bytes()) for p in runner.PORTABLE_PATHS}
            rows = ['100644 blob ' + blob + '\t' + p for p,blob in blobs.items()]
            with mock.patch.object(runner,'checked',return_value='\0'.join(rows)+'\0'):
                self.assertEqual(len(runner.verify_portable_tree(CURRENT_SOURCE,'synthetic',before=before)),4)
            for i in range(4):
                for mode in ('missing','mode','blob','duplicate'):
                    bad=list(rows)
                    if mode=='missing':bad.pop(i)
                    elif mode=='mode':bad[i]=bad[i].replace('100644','100755')
                    elif mode=='blob':bad[i]=re.sub('[a-f0-9]{40}','0'*40,bad[i],count=1)
                    else:bad.append(bad[i])
                    with mock.patch.object(runner,'checked',return_value='\0'.join(bad)+'\0'),self.assertRaises(ValueError):
                        runner.verify_portable_tree(CURRENT_SOURCE,'synthetic',before=before)

    def test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk(self):
        relative = 'tools/tests/test_run138_current_ci_entry.py'
        raw = (CURRENT_SOURCE / relative).read_bytes()
        row = runner.PORTABLE_SOURCE_ROWS[relative]
        self.assertEqual(runner.hashlib.sha256(runner.portable_f04_source(relative, raw)).hexdigest(),
                         '08766906799a3069dea21b563d6072fff81e543bb14ddc6938a9b5e043529367')
        self.assertEqual(runner.hashlib.sha256(raw).hexdigest(),
                         '2ee4f0dac630e697d10d06595a1ac257d50d49f9ef421ef9f0c1549e5f516f08')
        for mutant in (raw + b'\n', raw.replace(row['hunks'][0]['after'].encode(), b'', 1),
                       raw + row['hunks'][0]['after'].encode()):
            with self.assertRaises(ValueError): runner.portable_f04_source(relative, mutant)
        original = Path.read_bytes
        def read(path):
            return runner.portable_f04_source(relative, raw) if path == CURRENT_SOURCE / relative else original(path)
        with mock.patch.object(Path, 'read_bytes', read), self.assertRaises(ValueError):
            runner.validate_portable_selection(PORTABLE_SELECTION, CURRENT_SOURCE)

    def transport(self, command, root):
        if command[1:3] == ['rev-parse',runner.PORTABLE_BASE_COMMIT+'^{tree}']:return runner.PORTABLE_BASE_TREE
        if command[1:3] == ['cat-file','-p']:
            if command[3]=='a'*40:return 'tree '+'b'*40+'\nparent '+runner.PORTABLE_BASE_COMMIT+'\n\nCurrent portable witness'
            if command[3]==runner.PORTABLE_BASE_COMMIT:return 'tree '+runner.PORTABLE_BASE_TREE+'\nparent '+runner.NATIVE_BASE_COMMIT+'\n\nPublished f04 witness'
        if command[1]=='diff' and command[3]==runner.PORTABLE_BASE_COMMIT:return '\n'.join(runner.PORTABLE_LAYER['allowed_changes'])
        if command[1]=='ls-tree':
            if tuple(command[5:])==runner.PORTABLE_PATHS:
                blobs=runner.PORTABLE_BEFORE_BLOBS if command[3]==runner.PORTABLE_BASE_COMMIT else {p:runner.blob_id((root/p).read_bytes()) for p in runner.PORTABLE_PATHS}
                return '\0'.join('100644 blob '+b+'\t'+p for p,b in blobs.items())+'\0'
            if tuple(command[5:])==runner.NATIVE_PATHS and command[3]==runner.PORTABLE_BASE_COMMIT:
                rows=['100644 blob '+r['after_blob']+'\t'+r['path'] for r in CURRENT_SELECTION['native_repair']['payload_changes']]
                rows.extend('100644 blob '+runner.PORTABLE_BEFORE_BLOBS[p]+'\t'+p for p in runner.NATIVE_DIAGNOSTIC_BASE_BLOBS)
                return '\0'.join(rows)+'\0'
        return NativeC2afBoundary().native_transport(command,root)

    def test_new4_and_published14_15_34_19_scope_cannot_be_relabelled(self):
        with mock.patch.object(runner,'checked',side_effect=self.transport),mock.patch.dict(os.environ,{'GITHUB_SHA':'a'*40}):
            identity=runner.verify_portable_scope(CURRENT_SOURCE,PORTABLE_SELECTION)
            self.assertEqual(identity['source_sha'],'a'*40)
            self.assertEqual(identity['source_tree'],'b'*40)
            self.assertEqual(identity['portable_base_commit'],runner.PORTABLE_BASE_COMMIT)
            self.assertEqual(identity['native_base_commit'],runner.NATIVE_BASE_COMMIT)
        for mode in ('parent','merge','f04-tree','missing-path','extra-path','status','published14','dirty'):
            def changed(command,root):
                value=self.transport(command,root)
                if command[1:4]==['cat-file','-p','a'*40]:
                    if mode=='parent':return value.replace(runner.PORTABLE_BASE_COMMIT,runner.NATIVE_BASE_COMMIT)
                    if mode=='merge':return value.replace('\n\n','\nparent '+'f'*40+'\n\n')
                if command[1:3]==['rev-parse',runner.PORTABLE_BASE_COMMIT+'^{tree}'] and mode=='f04-tree':return '0'*40
                if command[1]=='diff':
                    if command[3]==runner.PORTABLE_BASE_COMMIT:
                        if mode=='missing-path':return '\n'.join(value.splitlines()[:-1])
                        if mode=='extra-path':return value+'\nM\tApp/Unexpected.swift'
                        if mode=='status':return value.replace('M\t','A\t',1)
                    if command[3]==runner.NATIVE_BASE_COMMIT and mode=='published14':return ''
                if command[1]=='status' and mode=='dirty':return ' M App/Unexpected.swift'
                return value
            with mock.patch.object(runner,'checked',side_effect=changed),mock.patch.dict(os.environ,{'GITHUB_SHA':'a'*40}),self.assertRaises(ValueError):
                runner.verify_portable_scope(CURRENT_SOURCE,PORTABLE_SELECTION)

    def test_portable_receipt_requires_new_identity_before_original65_checks(self):
        receipt,expected=ReceiptIdentity().receipt()
        receipt.update(native_base_commit=runner.NATIVE_BASE_COMMIT,native_base_tree=runner.NATIVE_BASE_TREE,native_selection=runner.NATIVE_NAME)
        with self.assertRaises(ValueError):runner.validate_portable_pass_receipt(receipt,expected,PORTABLE_SELECTION)
        receipt.update(portable_base_commit=runner.PORTABLE_BASE_COMMIT,portable_base_tree=runner.PORTABLE_BASE_TREE,portable_selection=runner.PORTABLE_LAYER['name'])
        runner.validate_portable_pass_receipt(receipt,expected,PORTABLE_SELECTION)
        for field in ('portable_base_commit','portable_base_tree','portable_selection'):
            bad=copy.deepcopy(receipt);bad[field]='wrong'
            with self.assertRaises(ValueError):runner.validate_portable_pass_receipt(bad,expected,PORTABLE_SELECTION)
        receipt['groups']['core']['actual'].pop()
        with self.assertRaises(ValueError):runner.validate_portable_pass_receipt(receipt,expected,PORTABLE_SELECTION)


class FixedPublicNativeRead(unittest.TestCase):
    def headers(self):return 'tree '+runner.NATIVE_BASE_TREE+'\nparent '+runner.BASE_COMMIT+'\n\nSynthetic c2af metadata'
    def present(self,command,root):
        if command[1:3]==['cat-file','-e']:return ''
        if command==['git','cat-file','-p',runner.NATIVE_BASE_COMMIT]:return self.headers()
        raise AssertionError(command)
    def missing(self,command,root):
        if command[1:3]==['cat-file','-e']:raise ValueError('Missing c2af')
        return self.present(command,root)
    def test_present_c2af_never_fetches(self):
        with mock.patch.object(runner,'checked',side_effect=self.present),mock.patch.object(runner,'execute') as execute:
            runner.ensure_native_commit(CURRENT_SOURCE)
        execute.assert_not_called()
    def test_missing_c2af_is_one_exact_bounded_public_read(self):
        with mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',side_effect=[(0,b'core.bare\n'),(0,b'')]) as execute:
            runner.ensure_native_commit(CURRENT_SOURCE)
        self.assertEqual(execute.call_count,2)
        args=execute.call_args_list[1].args;kwargs=execute.call_args_list[1].kwargs
        self.assertEqual(args[0][-2:],['https://github.com/liboyang42-cpu/chengyin-ios.git',runner.NATIVE_BASE_COMMIT])
        self.assertEqual(args[2],60);self.assertIn('--depth=1',args[0]);self.assertIn('http.followRedirects=false',args[0]);self.assertIn('credential.helper=',args[0])
        self.assertEqual(kwargs['env']['GIT_TERMINAL_PROMPT'],'0');self.assertNotIn('GITHUB_TOKEN',kwargs['env'])
    def test_bad_c2af_identity_config_timeout_and_parent_fail_closed(self):
        for key in ('NATIVE_BASE_COMMIT','NATIVE_BASE_TREE'):
            with mock.patch.object(runner,key,'0'*40),mock.patch.object(runner,'checked') as read,self.assertRaises(ValueError):runner.ensure_native_commit(CURRENT_SOURCE)
            read.assert_not_called()
        for config in (b'credential.helper\n',b'http.extraheader\n',b'url.bad.insteadof\n',b'include.path\n'):
            with mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',return_value=(0,config)) as execute,self.assertRaises(ValueError):runner.ensure_native_commit(CURRENT_SOURCE)
            self.assertEqual(execute.call_count,1)
        for result in ((1,b''),(124,b'')):
            with mock.patch.object(runner,'checked',side_effect=self.missing),mock.patch.object(runner,'execute',side_effect=[(0,b'core.bare\n'),result]) as execute,self.assertRaises(ValueError):runner.ensure_native_commit(CURRENT_SOURCE)
            self.assertEqual(execute.call_count,2)
        for bad in (self.headers().replace(runner.NATIVE_BASE_TREE,'0'*40),self.headers().replace(runner.BASE_COMMIT,'0'*40),self.headers().replace('\n\n','\nparent '+'f'*40+'\n\n')):
            def changed(command,root):return '' if command[1:3]==['cat-file','-e'] else bad
            with mock.patch.object(runner,'checked',side_effect=changed),mock.patch.object(runner,'execute') as execute,self.assertRaises(ValueError):runner.ensure_native_commit(CURRENT_SOURCE)
            execute.assert_not_called()


class DescriptionRepairBoundary(unittest.TestCase):
    """Synthetic source/scope controls, never evidence of Apple execution."""
    def fixture_root(self):
        previous = getattr(self, '_description_fixture', None)
        if previous is not None: previous.cleanup()
        temporary = tempfile.TemporaryDirectory(prefix='description-eleven-controls-')
        self._description_fixture = temporary
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for relative in runner.DESCRIPTION_PATHS:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((DESCRIPTION_SOURCE / relative).read_bytes())
        self.assertEqual(len(runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)), 8)
        return root

    def repinned(self, selection, root, callback, *, deep=False):
        """Synthetic coherent outer/row pins cannot replace an independent base."""
        raw = (json.dumps(selection, indent=2, ensure_ascii=True) + '\n').encode()
        (root / 'tools/targeted_native_selection.json').write_bytes(raw)
        import contextlib
        with contextlib.ExitStack() as stack, \
             mock.patch.object(runner, 'DESCRIPTION_LAYER', selection['description_repair']), \
             mock.patch.object(runner, 'DESCRIPTION_SELECTION_SHA256', runner.hashlib.sha256(runner.encode(selection).encode()).hexdigest()), \
             mock.patch.object(runner, 'DESCRIPTION_SELECTION_RAW_SHA256', runner.hashlib.sha256(raw).hexdigest()):
            if deep:
                pin = runner.hashlib.sha256(runner.encode(selection['description_repair']['payload_changes']).encode()).hexdigest()
                stack.enter_context(mock.patch.object(runner, 'DESCRIPTION_REPAIR_CHANGES_SHA256', pin))
            return callback(selection, root)

    def test_complete_original108_methods_and_decorators_are_byte_identical(self):
        old = description_7b_test_source()
        current = (DESCRIPTION_TOOLS / 'tests/test_targeted_native.py').read_bytes()
        self.assertEqual(len(verify_original108_source(old)), 108)
        self.assertEqual(verify_original108_source(current), verify_original108_source(old))
        self.assertEqual(runner.hashlib.sha256(old).hexdigest(),
                         '37b8a210e51c0c062964fedfd146313e53895fb255f4465db3eef0f0aaded993')
        self.assertEqual(runner.blob_id(old), '91937ee7b9690b80de047ac24bf0748bf95c50e7')
        self.assertEqual((CURRENT_TOOLS / 'tests/test_targeted_native.py').read_bytes(), old)
        self.assertEqual((CURRENT_TOOLS / 'run_targeted_native.py').read_bytes(),
                         (DESCRIPTION_TOOLS / 'run_targeted_native.py').read_bytes())
        self.assertNotEqual(CURRENT_SOURCE, DESCRIPTION_SOURCE)

    def test_original108_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines(self):
        raw = (DESCRIPTION_TOOLS / 'tests/test_targeted_native.py').read_bytes()
        found = verify_original108_source(raw)
        for identity in ORIGINAL108_IDENTITIES:
            segment = found[identity].encode()
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                verify_original108_source(raw.replace(segment, b'', 1))
        segment = next(value for value in found.values() if 'self.assert' in value).encode()
        mutants = [raw.replace(segment, segment.replace(b'self.assert', b'self.asserX', 1), 1),
                   raw.replace(segment, b'    @unittest.skip("mutated")\n' + segment, 1),
                   raw.replace(segment, segment.replace(b'\n', b' # changed\n', 1), 1),
                   raw.replace(segment, segment + b'\n' + segment, 1),
                   raw.replace(b'\n', b'\r\n'), raw.replace(b'\n', b'\r')]
        for mutant in mutants:
            with self.assertRaises((ValueError, SyntaxError)): verify_original108_source(mutant)
        with mock.patch.dict(globals(), {'DESCRIPTION_7B_TEST_SHA256': '0' * 64}), self.assertRaises(ValueError):
            description_7b_test_source()
        with mock.patch.dict(globals(), {'DESCRIPTION_7B_TEST_BLOB': '0' * 40}), self.assertRaises(ValueError):
            description_7b_test_source()

    def test_new11_old4_native14_15_34_19_and_original65_stay_separate(self):
        self.assertEqual(runner.DESCRIPTION_BASE_COMMIT, '7b882973b47dee412b9f0a95e9ad030798ab2ea5')
        self.assertEqual(runner.DESCRIPTION_BASE_TREE, '0b5e932191ef736a9a780438087b8476c5b2aae9')
        self.assertEqual(len(runner.DESCRIPTION_PATHS), 11)
        self.assertEqual(len(set(runner.DESCRIPTION_PATHS)), 11)
        self.assertEqual(len(runner.DESCRIPTION_PAYLOAD_PATHS), 8)
        self.assertEqual(set(runner.DESCRIPTION_PATHS), set(runner.DESCRIPTION_BEFORE_BLOBS))
        self.assertEqual(set(runner.DESCRIPTION_PATHS), set(runner.DESCRIPTION_PAYLOAD_PATHS) | set(runner.DESCRIPTION_DIAGNOSTIC_PATHS))
        self.assertEqual(runner.DESCRIPTION_LAYER['allowed_changes'], ['M\t' + p for p in runner.DESCRIPTION_PATHS])
        self.assertEqual([len(runner.PORTABLE_PATHS), len(runner.NATIVE_PATHS), len(runner.ALLOWED_CHANGES),
                          len(runner.PARENT_HISTORY_CHANGES), len(runner.HISTORICAL_ALLOWED_CHANGES)], [4, 14, 15, 34, 19])
        self.assertEqual(runner.description_predecessor_selection(DESCRIPTION_SELECTION), PORTABLE_SELECTION)
        self.assertEqual(DESCRIPTION_SELECTION['groups'], PORTABLE_SELECTION['groups'])
        self.assertEqual(sum(len(group['methods']) for group in DESCRIPTION_SELECTION['groups']), 65)
        self.assertEqual(runner.validate_description_selection(DESCRIPTION_SELECTION, DESCRIPTION_SOURCE), DESCRIPTION_SELECTION)

    def test_all_eight_current_payloads_restore_exact_complete_7b_bytes(self):
        restored = runner.description_predecessor_sources(DESCRIPTION_SELECTION, DESCRIPTION_SOURCE)
        self.assertEqual(set(restored), set(runner.DESCRIPTION_PAYLOAD_PATHS))
        for row in DESCRIPTION_SELECTION['description_repair']['payload_changes']:
            relative = row['path']; old = restored[relative]; raw = (DESCRIPTION_SOURCE / relative).read_bytes()
            with self.subTest(path=relative):
                self.assertEqual(runner.hashlib.sha256(raw).hexdigest(), row['after_sha256'])
                self.assertEqual(runner.blob_id(raw), row['after_blob'])
                self.assertEqual(runner.hashlib.sha256(old).hexdigest(), row['before_sha256'])
                self.assertEqual(runner.blob_id(old), runner.DESCRIPTION_BEFORE_BLOBS[relative])
                self.assertEqual(old, (CURRENT_SOURCE / relative).read_bytes())
                self.assertNotEqual(raw, old)

    def test_selection_missing_unknown_reordered_and_historical_layers_fail(self):
        for mode in ('missing', 'unknown', 'key-order', 'old7b', 'oldf04', 'oldv5', 'base', 'tree', 'path', 'duplicate'):
            changed = copy.deepcopy(DESCRIPTION_SELECTION)
            if mode == 'missing': changed.pop('description_repair')
            elif mode == 'unknown': changed['unknown_description_control'] = True
            elif mode == 'key-order': changed = dict(reversed(list(changed.items())))
            elif mode == 'old7b': changed = copy.deepcopy(PORTABLE_SELECTION)
            elif mode == 'oldf04': changed = copy.deepcopy(CURRENT_SELECTION)
            elif mode == 'oldv5': changed = copy.deepcopy(SELECTION)
            elif mode == 'base': changed['description_repair']['base_commit'] = runner.PORTABLE_BASE_COMMIT
            elif mode == 'tree': changed['description_repair']['base_tree'] = '0' * 40
            elif mode == 'path': changed['description_repair']['allowed_changes'].append('M\tApp/Unexpected.swift')
            else: changed['description_repair']['payload_changes'].append(copy.deepcopy(changed['description_repair']['payload_changes'][0]))
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                runner.description_predecessor_selection(changed)

    def test_each_of_eleven_current_files_rejects_missing_old_and_same_stat_bytes(self):
        root = self.fixture_root()
        restored = runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)
        for relative in runner.DESCRIPTION_PATHS:
            target = root / relative; raw = target.read_bytes(); stamp = target.stat()
            with self.subTest(path=relative, mode='same-stat'):
                target.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
                os.utime(target, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
                self.assertEqual((target.stat().st_size, target.stat().st_mtime_ns), (stamp.st_size, stamp.st_mtime_ns))
                with self.assertRaises(ValueError): runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)
            with self.subTest(path=relative, mode='missing'):
                target.unlink()
                with self.assertRaises(ValueError): runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)
            with self.subTest(path=relative, mode='historical'):
                old = restored.get(relative)
                if relative == 'tools/targeted_native_selection.json':
                    old = (CURRENT_SOURCE / relative).read_bytes()
                elif relative == 'tools/tests/test_targeted_native.py': old = description_7b_test_source()
                if old is None: old = raw + b'\n# Synthetic stale runner\n'
                target.write_bytes(old)
                with self.assertRaises(ValueError): runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)
            target.write_bytes(raw)
        self.assertEqual(len(runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)), 8)

    def test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected(self):
        root = self.fixture_root()
        for relative in runner.DESCRIPTION_PATHS:
            target = root / relative; raw = target.read_bytes()
            for inside in (True, False):
                destination = root / '.same-bytes' if inside else DESCRIPTION_SOURCE / relative
                if inside: destination.write_bytes(raw)
                target.unlink(); target.symlink_to(destination)
                with self.subTest(path=relative, inside=inside), self.assertRaises(ValueError):
                    runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)
                target.unlink(); target.write_bytes(raw)
                if inside: destination.unlink()
        for inside in (True, False):
            root = self.fixture_root(); original = root / 'tools'
            if inside:
                destination = root / '.tools-alias'
                original.rename(destination)
            else:
                temporary = tempfile.TemporaryDirectory(prefix='description-outside-link-')
                self.addCleanup(temporary.cleanup)
                destination = Path(temporary.name) / 'tools'
                original.rename(destination)
            original.symlink_to(destination, target_is_directory=True)
            with self.subTest(ancestor=True, inside=inside), self.assertRaises(ValueError):
                runner.description_predecessor_sources(DESCRIPTION_SELECTION, root)

    def test_each_payload_rejects_coherently_repinned_off_hunk_postimage(self):
        for relative in runner.DESCRIPTION_PAYLOAD_PATHS:
            root = self.fixture_root()
            changed = copy.deepcopy(DESCRIPTION_SELECTION)
            row = next(row for row in changed['description_repair']['payload_changes'] if row['path'] == relative)
            raw = (root / relative).read_bytes() + b'\n'
            (root / relative).write_bytes(raw)
            row['after_sha256'] = runner.hashlib.sha256(raw).hexdigest(); row['after_blob'] = runner.blob_id(raw)
            for deep in (False, True):
                with self.subTest(path=relative, independent_rows_pin_replaced=deep), self.assertRaises(ValueError):
                    self.repinned(changed, root, runner.description_predecessor_sources, deep=deep)

    def test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent(self):
        for mode in ('before-sha', 'before-blob', 'after-sha', 'after-blob', 'hunks', 'old7b', 'drop', 'reorder', 'add'):
            root = self.fixture_root(); changed = copy.deepcopy(DESCRIPTION_SELECTION)
            rows = changed['description_repair']['payload_changes']; row = rows[0]
            if mode == 'before-sha': row['before_sha256'] = '0' * 64
            elif mode == 'before-blob': row['before_blob'] = '0' * 40
            elif mode == 'after-sha': row['after_sha256'] = '0' * 64
            elif mode == 'after-blob': row['after_blob'] = '0' * 40
            elif mode == 'hunks': row['hunks'] = []
            elif mode == 'old7b': (root / row['path']).write_bytes((CURRENT_SOURCE / row['path']).read_bytes())
            elif mode == 'drop': rows.pop()
            elif mode == 'reorder': rows.reverse()
            else:
                duplicate = copy.deepcopy(row); duplicate['path'] = 'App/Unexpected.swift'; rows.append(duplicate)
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.repinned(changed, root, runner.description_predecessor_sources, deep=True)

    def tree_records(self, root, before):
        blobs = runner.DESCRIPTION_BEFORE_BLOBS if before else {
            p: runner.blob_id((root / p).read_bytes()) for p in runner.DESCRIPTION_PATHS}
        return ['100644 blob ' + blob + '\t' + path for path, blob in blobs.items()]

    def test_every_before_and_current_tree_requires_all_eleven_exact_modes_blobs_and_types(self):
        for before in (True, False):
            rows = self.tree_records(DESCRIPTION_SOURCE, before)
            with mock.patch.object(runner, 'checked', return_value='\0'.join(rows) + '\0'):
                self.assertEqual(len(runner.verify_description_tree(DESCRIPTION_SOURCE, 'synthetic', before=before)), 11)
            for index in range(11):
                for mode in ('missing', 'mode', 'blob', 'type', 'duplicate', 'outside'):
                    changed = list(rows)
                    if mode == 'missing': changed.pop(index)
                    elif mode == 'mode': changed[index] = changed[index].replace('100644', '100755', 1)
                    elif mode == 'blob': changed[index] = re.sub('[a-f0-9]{40}', '0' * 40, changed[index], count=1)
                    elif mode == 'type': changed[index] = changed[index].replace(' blob ', ' commit ', 1)
                    elif mode == 'duplicate': changed.append(changed[index])
                    else: changed.append('100644 blob ' + '0' * 40 + '\t../outside.py')
                    with self.subTest(before=before, path=index, mode=mode), \
                         mock.patch.object(runner, 'checked', return_value='\0'.join(changed) + '\0'), self.assertRaises(ValueError):
                        runner.verify_description_tree(DESCRIPTION_SOURCE, 'synthetic', before=before)

    def transport(self, command, root):
        """Explicit mocked Git transport; no fabricated real published checkout."""
        if command[1:3] == ['rev-parse', runner.DESCRIPTION_BASE_COMMIT + '^{tree}']: return runner.DESCRIPTION_BASE_TREE
        if command[1:3] == ['cat-file', '-p']:
            if command[3] == 'a' * 40:
                return 'tree ' + 'b' * 40 + '\nparent ' + runner.DESCRIPTION_BASE_COMMIT + '\n\nSynthetic new11 metadata'
            if command[3] == runner.DESCRIPTION_BASE_COMMIT:
                return 'tree ' + runner.DESCRIPTION_BASE_TREE + '\nparent ' + runner.PORTABLE_BASE_COMMIT + '\n\nPublished 7b metadata mock'
        if command[1] == 'diff' and command[3] == runner.DESCRIPTION_BASE_COMMIT:
            return '\n'.join(runner.DESCRIPTION_LAYER['allowed_changes'])
        if command[1] == 'ls-tree':
            if tuple(command[5:]) == runner.DESCRIPTION_PATHS:
                return '\0'.join(self.tree_records(root, command[3] == runner.DESCRIPTION_BASE_COMMIT)) + '\0'
            if tuple(command[5:]) == runner.PORTABLE_PATHS and command[3] == runner.DESCRIPTION_BASE_COMMIT:
                return '\0'.join('100644 blob ' + blob + '\t' + path
                                 for path, blob in runner.DESCRIPTION_PORTABLE_BEFORE_BLOBS.items()) + '\0'
        return PortableDiagnosticBoundary().transport(command, CURRENT_SOURCE)

    def test_new11_scope_authenticates_old4_native14_and_all_older_domains(self):
        calls = []
        def transport(command, root):
            calls.append(command)
            return self.transport(command, root)
        with mock.patch.object(runner, 'checked', side_effect=transport), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}):
            identity = runner.verify_description_scope(DESCRIPTION_SOURCE, DESCRIPTION_SELECTION)
        self.assertEqual(identity['source_sha'], 'a' * 40)
        self.assertEqual(identity['source_tree'], 'b' * 40)
        self.assertEqual(identity['description_base_commit'], runner.DESCRIPTION_BASE_COMMIT)
        self.assertEqual(identity['portable_base_commit'], runner.PORTABLE_BASE_COMMIT)
        self.assertEqual(identity['native_base_commit'], runner.NATIVE_BASE_COMMIT)
        self.assertEqual({command[3] for command in calls if command[1] == 'diff'},
                         {runner.DESCRIPTION_BASE_COMMIT, runner.PORTABLE_BASE_COMMIT, runner.NATIVE_BASE_COMMIT,
                          runner.BASE_COMMIT, runner.CREATOR_COMMIT, runner.HISTORICAL_BASE_COMMIT})

    def test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout(self):
        modes = ('parent', 'extra-parent', 'missing-parent', 'base-tree', 'base-parent', 'base-extra-parent',
                 'missing-path', 'extra-path', 'duplicate-path', 'status', 'old4', 'old14', 'old15',
                 'history34', 'history19', 'dirty', 'sha', 'tree-mode')
        for mode in modes:
            def changed(command, root):
                value = self.transport(command, root)
                if command[1:4] == ['cat-file', '-p', 'a' * 40]:
                    if mode == 'parent': return value.replace(runner.DESCRIPTION_BASE_COMMIT, runner.PORTABLE_BASE_COMMIT)
                    if mode == 'extra-parent': return value.replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n')
                    if mode == 'missing-parent': return '\n'.join(line for line in value.splitlines() if not line.startswith('parent '))
                if command[1:4] == ['cat-file', '-p', runner.DESCRIPTION_BASE_COMMIT]:
                    if mode == 'base-parent': return value.replace(runner.PORTABLE_BASE_COMMIT, runner.NATIVE_BASE_COMMIT)
                    if mode == 'base-extra-parent': return value.replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n')
                if command[1:3] == ['rev-parse', runner.DESCRIPTION_BASE_COMMIT + '^{tree}'] and mode == 'base-tree': return '0' * 40
                if command[1:3] == ['rev-parse', 'HEAD'] and mode == 'sha': return 'f' * 40
                if command[1] == 'diff':
                    if command[3] == runner.DESCRIPTION_BASE_COMMIT:
                        if mode == 'missing-path': return '\n'.join(value.splitlines()[:-1])
                        if mode == 'extra-path': return value + '\nM\tApp/Unexpected.swift'
                        if mode == 'duplicate-path': return value + '\n' + value.splitlines()[0]
                        if mode == 'status': return value.replace('M\t', 'A\t', 1)
                    if (mode, command[3]) in [('old4', runner.PORTABLE_BASE_COMMIT), ('old14', runner.NATIVE_BASE_COMMIT),
                                             ('old15', runner.BASE_COMMIT), ('history34', runner.CREATOR_COMMIT),
                                             ('history19', runner.HISTORICAL_BASE_COMMIT)]: return ''
                if command[1] == 'status' and mode == 'dirty': return ' M App/Unexpected.swift'
                if command[1] == 'ls-tree' and tuple(command[5:]) == runner.DESCRIPTION_PATHS and mode == 'tree-mode':
                    return value.replace('100644', '100755', 1)
                return value
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=changed), \
                 mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), self.assertRaises(ValueError):
                runner.verify_description_scope(DESCRIPTION_SOURCE, DESCRIPTION_SELECTION)

    def test_description_receipt_requires_new_identity_and_still_requires_all65_actual_results(self):
        receipt, expected = ReceiptIdentity().receipt()
        receipt.update(native_base_commit=runner.NATIVE_BASE_COMMIT, native_base_tree=runner.NATIVE_BASE_TREE,
                       native_selection=runner.NATIVE_NAME, portable_base_commit=runner.PORTABLE_BASE_COMMIT,
                       portable_base_tree=runner.PORTABLE_BASE_TREE, portable_selection=runner.PORTABLE_LAYER['name'])
        with self.assertRaises(ValueError): runner.validate_description_pass_receipt(receipt, expected, DESCRIPTION_SELECTION)
        receipt.update(description_base_commit=runner.DESCRIPTION_BASE_COMMIT, description_base_tree=runner.DESCRIPTION_BASE_TREE,
                       description_selection=runner.DESCRIPTION_LAYER['name'])
        runner.validate_description_pass_receipt(receipt, expected, DESCRIPTION_SELECTION)
        for field in ('description_base_commit', 'description_base_tree', 'description_selection',
                      'portable_base_commit', 'native_base_commit'):
            bad = copy.deepcopy(receipt); bad[field] = 'wrong'
            with self.subTest(field=field), self.assertRaises(ValueError):
                runner.validate_description_pass_receipt(bad, expected, DESCRIPTION_SELECTION)
        for group in receipt['groups']:
            bad = copy.deepcopy(receipt); bad['groups'][group]['actual'].pop()
            with self.subTest(group=group), self.assertRaises(ValueError):
                runner.validate_description_pass_receipt(bad, expected, DESCRIPTION_SELECTION)


class FixedPublicPortableRead(unittest.TestCase):
    """Mocked public-read boundaries only; these tests perform no network fetch."""
    def headers(self):
        return 'tree ' + runner.PORTABLE_BASE_TREE + '\nparent ' + runner.NATIVE_BASE_COMMIT + '\n\nSynthetic f04 metadata'

    def present(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        if command == ['git', 'cat-file', '-p', runner.PORTABLE_BASE_COMMIT]: return self.headers()
        raise AssertionError(command)

    def missing(self, command, root):
        if command[1:3] == ['cat-file', '-e']: raise ValueError('Synthetic missing fixed f04 object')
        return self.present(command, root)

    def test_present_exact_f04_never_fetches_or_reads_network_configuration(self):
        with mock.patch.object(runner, 'checked', side_effect=self.present), mock.patch.object(runner, 'execute') as execute:
            runner.ensure_portable_commit(DESCRIPTION_SOURCE)
        execute.assert_not_called()

    def test_missing_f04_uses_one_exact_bounded_noninteractive_public_read_without_credentials(self):
        environment = {'GITHUB_TOKEN': 'synthetic-not-a-secret', 'GH_TOKEN': 'synthetic-not-a-secret',
                       'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'http.extraHeader',
                       'GIT_CONFIG_VALUE_0': 'synthetic-not-a-secret', 'GIT_SSH_COMMAND': 'unexpected',
                       'HTTP_PROXY': 'http://example.invalid', 'HTTPS_PROXY': 'http://example.invalid'}
        with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', side_effect=self.missing), \
             mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute:
            runner.ensure_portable_commit(DESCRIPTION_SOURCE)
        self.assertEqual(execute.call_count, 2)
        config, fetch = execute.call_args_list
        self.assertEqual(config.args[0], ['git', 'config', '--local', '--includes', '--name-only', '--list'])
        self.assertEqual(config.args[2], 10)
        self.assertEqual(fetch.args[0], ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                                       '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                                       '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                                       'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                                       'https://github.com/liboyang42-cpu/chengyin-ios.git',
                                       'f04f1cab7ef92afcafcdbde411dde71b4a605820'])
        self.assertEqual(fetch.args[2:4], (60, True))
        safe = fetch.kwargs['env']
        self.assertEqual(set(safe), {'PATH', 'LANG', 'HOME', 'GIT_TERMINAL_PROMPT', 'GIT_CONFIG_NOSYSTEM',
                                     'GIT_CONFIG_GLOBAL', 'GIT_ASKPASS', 'SSH_ASKPASS'})
        self.assertEqual(safe['GIT_TERMINAL_PROMPT'], '0')
        self.assertEqual(safe['GIT_CONFIG_GLOBAL'], '/dev/null')
        self.assertEqual(safe['GIT_CONFIG_NOSYSTEM'], '1')
        self.assertEqual(safe['HOME'], '/dev/null')
        self.assertEqual(config.kwargs['env'], safe)
        self.assertFalse(set(environment) & set(safe))

    def test_f04_credential_redirect_include_and_auth_configuration_fail_before_fetch(self):
        keys = ('credential.helper', 'credential.https://github.com.username', 'http.extraheader',
                'http.https://github.com/.extraheader', 'http.proxy', 'url.ssh://example.invalid.insteadof',
                'include.path', 'includeif.gitdir:work.path', 'core.askpass', 'extensions.worktreeconfig')
        for key in keys:
            with self.subTest(key=key), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', return_value=(0, (key + '\n').encode())) as execute, self.assertRaises(ValueError):
                runner.ensure_portable_commit(DESCRIPTION_SOURCE)
            self.assertEqual(execute.call_count, 1)

    def test_f04_unreadable_config_offline_and_timeout_fail_closed_without_retry(self):
        for mode in ('config', 'offline', 'timeout'):
            outputs = [(1, b'')] if mode == 'config' else [(0, b'core.bare\n'), (124 if mode == 'timeout' else 1, b'')]
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', side_effect=outputs) as execute, self.assertRaises(ValueError):
                runner.ensure_portable_commit(DESCRIPTION_SOURCE)
            self.assertEqual(execute.call_count, 1 if mode == 'config' else 2)

    def test_existing_or_fetched_f04_wrong_tree_parent_merge_or_missing_headers_fail(self):
        bad_headers = (self.headers().replace(runner.PORTABLE_BASE_TREE, '0' * 40),
                       self.headers().replace(runner.NATIVE_BASE_COMMIT, runner.BASE_COMMIT),
                       self.headers().replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n'),
                       self.headers().replace('tree ' + runner.PORTABLE_BASE_TREE + '\n', ''),
                       self.headers().replace('parent ' + runner.NATIVE_BASE_COMMIT + '\n', ''),
                       self.headers().replace('\nparent ', '\ntree ' + runner.PORTABLE_BASE_TREE + '\nparent ', 1))
        for existing in (True, False):
            for bad in bad_headers:
                def read(command, root):
                    if command[1:3] == ['cat-file', '-e']:
                        if existing: return ''
                        raise ValueError('Synthetic missing f04')
                    return bad
                with self.subTest(existing=existing, headers=bad), mock.patch.object(runner, 'checked', side_effect=read), \
                     mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute, self.assertRaises(ValueError):
                    runner.ensure_portable_commit(DESCRIPTION_SOURCE)
                self.assertEqual(execute.call_count, 0 if existing else 2)

    def test_fixed_f04_public_object_identity_cannot_be_generalized(self):
        for key in ('PORTABLE_BASE_COMMIT', 'PORTABLE_BASE_TREE'):
            with self.subTest(key=key), mock.patch.object(runner, key, '0' * 40), \
                 mock.patch.object(runner, 'checked') as read, mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_portable_commit(DESCRIPTION_SOURCE)
            read.assert_not_called(); execute.assert_not_called()




if __name__ == '__main__':
    unittest.main()
