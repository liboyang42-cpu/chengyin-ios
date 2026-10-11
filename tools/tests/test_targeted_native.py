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


SOCIAL_42_TEST_SHA256 = 'cf610cfd2794c66d486d67c73ddaba93d34cb5f688635dec28b754dce01834fc'
SOCIAL_42_TEST_BLOB = 'f691ef11ff509c7680edb02e706b7ac3748a8caa'
SOCIAL_42_TEST_PACKED = (
    b'c-m~dX|t+K+P3+<e#LExmf}k_&JcnqlOs+jh#f66ipn6MOzLlM@27fO(cSM}5qklV<N;~smFIb7y8ijkfAWrcyZx`f!qkn<W@PJs'
    b'8Mb<Iz3}ft-E*VByM?{KT<@=;@88V7%*50mk?pyEdBI<S>3g9ac|rOu>f2`c?|=UDpZ~BO-wUF@ucUvD)yPcj=yw+W4*&D(W^4cc'
    b'R(kt$^%8pSpJOllhZT6vU%nchzvcd)JN{aIPyZD0Z+7^19e>UP^UqOepIr4<ZTQgqz|+kz{9Q?Zhmq;{mVNu(`f%+iGQUsyKlDFm'
    b'fAEf{U;pus?Q%Ki|HA+0VJfox_wBM={dZu7-tB2ts{i)Yz;vVV|E&LC{|J3k{}%m!zwp2RzAFDs_|MHZPgnnL+{(WqH8`1(X~^#P'
    b'!qb$4hwGZbzy8->|6%?gfBoxwMgISk`nR9{tNM@s6#f6R9M5=s8UI83n_Kz&zv}-y*uQU{YM8;l|NeC4|CFozr<&?NXojaYlht;z'
    b'T*zHg-ZK1F=EuWEyYof-tJ&2MwNZ!7c3p>cxYIy8Ez2}4qu%N?>rJ!WM9{XSHQH^f)#|hjt!bJTY{BZ6XP{{FU;o?s$@!A}yLPmW'
    b'HoK<T)zA(KYY1$ZaI358jh1G?-4>!*Xj^Z?X7_(z%W6o?82VdJ<sW~2|7riyp}>Aim%*ibeaXW#+fR(s({Wbs=46D{Zc&XvnB7h>'
    b'op~>d^%FEC8r`EholE{Kt{?2?aBx5AH$ZsJ%;_uH90y&EInqz87m@2kyj+7}<@+fAVP(Obv2J{F6VX!ml;UT@i_h=lUGolEqc+`R'
    b'`g>6#cYM(?y!)&*1eMZkU(sx<aXYRG1XiOeKyshjM89+f)W-E8G}^5oI=0tEa+f`zm-D#)VO`E`h$Q=$oZJt=(+2L$7xnyESxk?e'
    b'<W}rdle0FOq{wr?PYamRTp(TYHay|OmDj-w>p?DS+reV{03WT8ot|&?MY)-XN~krKxX>K)yJ#g}{;;sJ{}4yY#UGtL#4qE!I@V+9'
    b'_szLQLWRQ`2BcvK&I}#B`rbuX!!1C~&a!@6VAgRXTI0)fU*(R&@j74Eee<=JSxI?ZaCURj#hcjPqjrY<VF_x^Z@s3FG}rGB5ZVGW'
    b'Zv?aJC|$JLv+Hb^b|pk;mD$s11AL~79XuK0>Z*J2+~%@YBa=EP-pSMB@P?e7L_CjEwDo|YvP3v6ENuzzP51VHSkyzSnc#Y_TLb#O'
    b'^zljW1Q2)5n#9g|IA6-O_nXjri}u*ZTquz1=sbA<qP*X{7Ca2yTKRO|KUc6q|MH<A*n8b$N;>$9<zZPm1j{3DUMk~1tX^|Uwuqbn'
    b'TgL}?tW&*GkypFJhJ9mH1^2F>n7q%0mo*vSB5fjMpRdwbxbuk)9vZXBBN>>S24Af~To{{TyS@@#3>Y{RS}iQ-5Y0oDDg0q6%`*yd'
    b'gMw1ppVDV9BaagX$I!)Vr<}84!cXQPQ6cm7J#dd&98{eCU7ViC*Q9%ejQzfRf6RgQVfG|P{J6zz-|Vn=9edc`o2)m@Wp6#cPAh*{'
    b'6Kf0&o%5yMvb>enniV>A!=l4}nO9_Wt*)k~U9Asl>@I07;%*mL28?z+X#I2R{c)OcT3rVBiR0wt>#U6C>pt-Q6x_X2Di1cp&$pon'
    b'a~J+$S=#h14TJZoBNbY;rcahU&THY?Myg0=DUFBx3INNmoVni{@V->w`Zp#06sg6Gk_za_fVWi)IKs50+J&>*5W_S(t{yaz+r02;'
    b'm(`4^wEwWg;+A!E+gsb+M5$ho_5x;`es|fW(zA2{D#07sXXP3jIke3!vV@Z;$7>UpE8gM09Z8DKStB`E)X+bq19{s7eF+(qwS1GU'
    b'(Pjr>Q8eEDVRaQEj5MEYK;>LxCI1kHmg8>Me%HNd;60|}B~)l7H58HzeYDNV6y*l1Kr2?MVUKf)=bnAxm<@TKm`N%~9enl7;sn5r'
    b'JOZxJmK)ds@P{S)LLL>>5x&7a8u>^Ah4A95a+(jfyk3<7w*=`ue%_xZ0l9s(UxdjJyXMDt^00%2T8&>PyYQu!M(f@!OxtKb>P}7F'
    b'(!G6!Gb=*AiLcQgRy0})`2;=A5VxOStf03FUpLl|$Kj@HoK1Y&IkddA7t-J=Ixccy761nGfbr}iauB(T4B3mK<vunKz)_;R<Ke5>'
    b'zj~z`3=!>mf(vY`Is3y(^*}fblc{Etm6S&u=gzh=2xNG3Q%H@AT4ayo{rrVIliIN2808W6=yB21c=eDOS$<ElC){3`MV}gI!y=5g'
    b'7{jHzYV&Lk&DVs(bm}py{bAWXH>v{;kc4wDe?P--)K}JA1qS^GzxwEw(%3TP0UIboOINb?xQ+HUaaE$p(_%BVrW?z3CbJb?(FE@9'
    b'FDR}y4E=M)Kht9MQJx3`gt-!bSe1`>B*0JObGawY+1k8;!F%K9MAmpmFJA38uCDM#I``o{X>2-vxFpzUv9hUzdQ{zS$L?6%jXoHM'
    b'RV~@&S^yM;a=1;w+I?4}o;$B6yj#C`NWa`}`&j$R!=l@1hL`@a!S*GD_kysyd0sj6<3b;;s;vD{zJt4&T<i<7I+uI!V|+p;wq%Yj'
    b'xNN(%J!PptJWiFJJY@l*zJ@j`kKzk@D*s{OHd3B;_SN#T=y6&&5G#9XotKJ|rS3Wj`52CNj&x?^`Qb8gF&REgXYz<%P$%M1p1r1q'
    b'yRuB?epvL0tCoc;y6ddFN_}_g6$|8fpX|dL)c?bJ(bLc(M@kMJ0$(JS+}YALz|%r{Azx)E2tDntMo@xR#9SlY#mLoq5-!M%)e4$s'
    b'8$wrN>J%?6xxe;&Ill8&_B!ns!_iyCR@Syp7b+6-hZPs;MpJ2ma^G+)_|_U7FT84XHt4L|*ma7)2U(O}l-e*FwJ~}u%(&7{KF>Ns'
    b'`k|&R-yFDly*9c{nyZB=jXV{tUzf;{f6i8yv+y(?+ju_v&C3oC1FHhIx5tZ9VILbTJ7hMGM66Mtc!)~v=vvT@WU>e51&le(I#We3'
    b'i2P$Evo?B1!w)X4LqQ#6`~5Zt<||xSEHK}2P6d$MSJ|6B6(0N_md?C7)3U(Hl~UIV+G~wJ4}10Jhp088&1#|B74$XsHh`)qzTy$='
    b';?%d6{w)_2&Uy_A&EW>M+xZb;uUeb@M$$$<?Dg}eiZu_8b<z&Pm1zCu$}LT0?R6s^-Nb9J)G0uFSKE)JJJI^w=7n1=UOnKMU0##Y'
    b'<K5f_){r}`*(V`Qf^VmNeA|}_Guxkc=7CaeY2Dg+Q_AiHAxy>N_JV~?%1r;T+LKVUDxt9cpjTxUlGWs}-D~^|n5;^EuYxc8k6Np>'
    b'S$)OREgEzNGlqS?qO5$hT0-Z{CyOd0j@Vp$H2Uj1Xky^}HG)S6!`2HqMWjS+Hx~b}2DGY^gL<fY&E%0Kpf0=*u4}c&bzxL{bSLnE'
    b'nx*z=mw^+1GU=D8<~eu>y`4LoaWNGEwZUdx*w<hnCZ`>6uGD&*+_N<}dR(|<f)bCSviZZhiplo80#y6nAZ*flN}Oh{fhi!6Ph<x5'
    b'?z)i}I@E8OMccZ;0!FCMl~zkfH2@O}lULRTjJ*ObYaXhLs-ax=%mD_=*?ZjHx}R=&G^^H@zZjK@Alyve3KukorR=!4;3wz_SH*0&'
    b'=-#S2%$i2`@Z9V8sU%X}#g(MRsIZf%Q=Mqx>Ogb>4yH}+a_8MNmamP<<GGO+r0(G5Y$R&A(VYIY&CqX(3(pxOmT*yD^0Nb?%f@+Z'
    b'dc|hrGjOIm(3pIj9?PH`5IcXm467M)W4skFN0d$+Q0b2cTN)g5ldpRKS_QkZOMqIi(?|kcHut*i(|=e`Z}F0uG+{=bm>$R3^MI6L'
    b')1`1czjIv^ta4X=%2pxvxvIikO<?DvQtLan<5OK$2U=((KHH}1QA^0`PMy00y{^7&Xs_ysY1$ihGEa`{-@GihDbvJC96AdV_^|aV'
    b'^>dxHRT0!*iZ34Iz?*}o5w?sH1xLV7@HiN4c{6h&fzp@xvm3t$L-JNZrCBj4a!k(@%k}Om3d)7bs!FJ%gZ$G`#r)}i(%CwGcVzI1'
    b'9httdrcz%<iX#HN!%SW{KjPKtZTGlXTC~{HyYYM-S!h=S7rC?q`fFpDW%yFQ;%V3IM|DFzwiBh+m=@Xz(+&!${{F*K*F=?<`D4F7'
    b'$g4>*&~L)(ywsv4D}E|o_W&22{gAO{IJT>7!TGglrI#I39(kNti%C`Eyk6fsmVg>{9{{DSf4;1RW$(4E5<M^}7&Ghha{sXQ?+3It'
    b'$~5CTwSz@g+G7H=X&`u39t~#SeXpn8UI)I_Nn-f1+_zvD_0LIp42)fGzcAR(1U<*o;?lO&(n%I1wmX`gf!P8kW(wSqgXDd<{>In+'
    b'79t0;H7@6^!osbX7YisF%KmccVa2H5INF87Rw5{3J6pnd0rM}-K_QP?Kwq>!=kN7P(-Ov=CogOlQ+0NyyIv{l8q>yA!8Yl0RXHX6'
    b'uMHo7OkWn;Ie<)yelOO8D__g*B}&Zw3&KO|r0I5KbR+aYsRwAQzQ5_O7z9)&j}L*_1v6+{k57ccR}e8;=ju_exSq$lx_nvsTIOX{'
    b'QTpk_uX(?A5WT=dw6ra?i<7D*FcYR6aZoYsGP-aSQ<QBDa6+nz=iHy<GcJENVaBtL{KC+g4ZJ^hy0t_gDPnlLn#DDDm(tHQ)Dk<z'
    b'#!!t1e=LcRN_O*WEQ0eWjo3$%IJJe<NpG%<S6`_-P*wQ6m%_ETf>!CFqcFn}JS>hf`8gy@&T1*Ugj1Yh-?(}Wtj}$=n2B$!M@?&R'
    b'p*lRDo5g+g53AIbce@6=-@@*F=Md}R{SGXK+Z}ve)VLN-#`injVo9mg;JYX7xuW~y+thdWlG73CK1OS;NnQl%&O11Eb){Bc=IsI4'
    b'eld#QE??;SP@XM*dS2K(){JomT~s(^D$Qv=74?w&u?efelzNQyLb_GVRKAKst=H8W=a-Y#cX<V_Fgkuw7@eTrD8HazeC$HE3r$;}'
    b'n)Bew;z!RMvBvpO!}`MlJPk4>0yzZsI66Jq<wZ(&mu^xn^ol{Hpo{1tC-?P`Su=3`K6!TGem}9-lg)u2`#0b|1*K$m*a&`Gz9KKq'
    b'ue|EpiaDTGj5rx~(k@aql|QUPg&W+Q#ttSAamFm#(NVExPmdlmp~1cN5(m5%q^XLti!~`w@o39)6E%>#`GgbO2CmHSt6;6(=lz7u'
    b'L@y}HPwxnhE>U4$K%h#H;X3O7VU^$cyT}W1f1non<Ft-hTbjg#=?OAjL0unlzA^+5`UQwf;#n;FtPWP(GKEHWwba-MnO{%ml~wv4'
    b'8oAn<bMlQIkE;p|HuhR=RO?RePBi$#I)WG)T0N)PM`{MS?d1C%UOMy(+*wCQjc^_o$J_PnG&BY$%AXv2&)$5yo%HHuWT`O9Fd_#M'
    b'UH#58tIQr?N68BGGB6;Qr8jJHu;5w&?H~WJq+l~^jHS6GOmFO<$7`LZ=8u3qSawy55AuL(?jN0E{+)=}tcAYl0wD~;w&kARy=85k'
    b'L+O_-zUmcXw^;g_(Ji6^Q}K;#eIvPjgpJVCFK+l#W3CkM@Z)@jWujbop(LTKI?LUvyjK~YC9jROy>qK}qlMkMs8m|8#p$8JZ3{|_'
    b'mLO>&EGWOEe8i<+<hlfEusI3Zk5K;{6&l@k*ys9}2e7xIlUi>R4{pn|(P)?I1Aenk^~@)oH)L}vOwd*Wo@T3C>pDsr@@uij@<u_P'
    b'N=tvCvK^B5m8nUg<f(MrN@R=LW;oWw9>?^BwUmQ885)0BP{plE`V0*RcfE5N-nOoc>>6!Te9Zb_?pFeo>WwGV?kh}3%;W%KHr%$9'
    b'T`+8%%kA2vS1EPwcqN<8wZZx_grBo1dd$fl`)D`2VS~@C*6ZgTx>a&7v6a(vHBx)j0pb>@Z0se<qitFbt#Z8>E#&1cDlX55QU@B8'
    b'J*0l-c(&4b!#n5vm1diDq{^1|6_JIo9I-6a>RG!2(6Yc<XH0WoXYz;T6%E1bUko>wV@ueu)WIzfClt6p?f8lB9Znn)RH7T4F;vvS'
    b'd$XS<wa#E&7{3N<gzYY|=dF1^r*k+S!!^wUFu1e7G2&%8SfU|mG7H5h|6wiG!;@6JKjjv(3)5pGmF{OHGM@u@kFD?QH4aLf6jICj'
    b'Aj9h2H4?&R9D}#@CwKwCoUnSm;(UZ!sv9lQ<6h;`P3;~EZp~~?N{f}FH0-kZhs7Gl*F3TA`K2@V$Kd*dZ@Z$;c{-W|pQ=@K2>Li*'
    b'-ywJ%&Ex7^V3`u!LTkC=Y(7)3+L$G2lpxp9yo=1Po2i4{`^v;#!~H@&8XOKz*#dua%1St#nStj7_HN#+94GNn&(r&h31xYzDELR1'
    b'5m)@kImc;XJIo4Oga<nJibg#20(^J?pQqHTZpo2&o<tmo)?NgUh?`CeYG2UYh@1oSzWn-OhYp}hWe?%4=LHqtJF>yy;eIw<UGu&X'
    b'e?wRCaXar85Ak&G)|>*~*nmXn*2@QFdyHG{0vFt^(+mc@^_ptBH?Q;^HKXRa;bETPL(-);@y~x)q({>HXiThk_o{w2TAyI)Vq;}n'
    b'U^qEH08~>h%*H@b>rq{0J6Ji~*@Ue3sdX;79>4ExMgTeQ7`ejjC!>9>)7YNRr=lW)NO{n!*wfKgG=x7aLh5)C26g83X{YZO!$#jr'
    b'^3*8j_Cbl7&bksIV-;!&O=aC_4;gU2IL;sEZY4W^ZiUi9%#AH~J!dhr=cUx|9!{;|a$6h9^=lFH!lWdD$uCF5g4J@&So&SJ!HntQ'
    b'KsWyg<3U)uip!k-M#L9d$4Ji@OL-T%4VKGfLL#5j=1!F?tT}9F8w$>#&GS)s6_#)*$_$WMFb~|l-_tfUtybNM_VW(-_3=c9<W%~O'
    b'%&9!>jEKo2EZNm|@N@{F?6K&nqONecQuhpnak9~jX`stC6kYSO%vX95qB`yf!1?d^-o`GGRXNIeL|;)y%~hO8Z@_>1hW30IbKUk<'
    b'=MO(T^^%@Yz0|k(eci>v+Yo;TYv+oOSDRdamDKs@iEBjonH&8hKyb%q8^11&6LT8Iq8o12&f-B#VX}wyTVFX~I}q`74!_*;W1WW$'
    b'`uJ|cptfqx&BgU3?xtCb-iXd6sZ6i88u8L5yA3G{aC4mxlRX-%t(l)+TeJD%$`KrKAp6GdJ<6A*bF;C@b1f7b1-(0!&F0Bm?SAVH'
    b'fVyew&-MZ-(zs!Fb>e!jAS}=TwdFlh?__nlyS_M^m<^LfqjL4OlxD5`YW!@_Bj{Z$$zTBl2cSJXexj$*(FT?M@Xq@8<be^n@77ak'
    b'|I^s@Yr8~tC!|1e3Xg}+7Ri^cc65Csk7>ME%_>mBIi6&eb)QHToH%M5bdZ6&2Jff?cEG>De)@Ws^zqhnU6<<#&(~%t-PWy2AL8Ec'
    b'O;;7+-+K|W{Xx~%rHVG_nKSNKV7q{_JEl%uqdu2a=OdXgk^;4<2o(WtEA@^Y`y?d%<g3|{K|#HV;P#j$kKr<f?)7NaLko4PMb=M6'
    b';&r+%i*AJe@@(}duR(1@t}_Db7mH$>ZmM_!q+aD7PXlMD>h3<NQD|+i=gLUf;oYeP)E>g2r|&lKH;6f<+l*bxzPG7uI!7}((W~@z'
    b'qc`y}mTNmZU;X;Vn0WCAahIoP1rrEZ9VJfXI#Js6_5;Ok=2Zy8w8}Vji0<|J^?s=J!P>E9iSVmgKkw_}EXpPX7i%>o3dVCAg^95^'
    b'=PKMoity(a^n?W7{$Z`b>=1w+S9i@gFg0y9UDmVa<B{i0EZw-3`s#W@Eua&xJ~pzcvy3ygLZCUlLS89+t#P@4>&L@D;9hJtPB6z0'
    b'TTm^p%r?X86W>$@%$xn?V3l%#Jqa+txAailBS`)6dCY4yE<OMqpO}qUfap|9g%;hQ9tqTFY)Vck^?^EBQX%#r(W8?#nGt=3?!F{l'
    b'ZmnM2jWm%kUQiqI&_QjjGyLgZtkU1*4gH*9S$A08(T#xB_v@M3&AVsuL*Eb20YR;lrCHK|DXM*lP3;;!>V33y3SfM{jub;=OX&8}'
    b'4!*NY<JH3AY95Zpn$fy-v7`OoJ%4@U){lCHx-MjFQa%izK6D4-EOlyQwNDA_-gmyfyW?*Fy-Y&Ss)1XyhPlID#5Ebw93AiDXr2b^'
    b'3W2ZgBXda<DleqAS36~wy)<i^^j+9;OX=4){4!v4(AJKz*R!t`EKc|pSJb*4!}tv6&eDOZ>;5hKip0jP%-^MTKHIpjqM*6v{XAr`'
    b'`eBvL0s`GL3IP_v&lY50rnIOX>z!NrRu<d)miogo=6CL`RQZow!I7#tvY+$y!`~?9JdNhNe%NB<Olvu%A+;-L97{fyQvMw!H>mIy'
    b'pb?nVD<x)c$ddIDPh(6xc6vmiyWGjkBQRxd#{{O7-#YB9s`Q;;As&Qc`&e%=EnhgD(}5FrXbjiPSTcm(F1U86<6sy0!#9BWDOIR-'
    b'`$MMPRc3Q*hxKuFEzT23T)l2Z+tcf%d3tJa(vnH$hfzZPv<(@p4-b<Ut+d2Vca7WIpA70sudhh=SIOAkk{2eqL4U!|<eENa8W+>|'
    b'i`tRBL`nGleAY5Z&re_XWMCtAKuROf8=&OqaUCEljC1cAlu7Cz)^LBhoaQ(>Uy1gniC*r>IJBEWHbo7tolsdk{l<Ap9}%mP!&~LE'
    b'aF~RHLQoSnNRzV$`bU<!Qg^PPI}n}&k9)Ui#5kjX9+{7-q0h{S+3gSORR4})I33xmodHl&b_pP;S3J)Zu?}5aRC6AVyzQ^@8D;kt'
    b')HQ{);Si9_Q64{;0PHscp0{f@Nsbo1ReWTJMJoW2!ENtkNPXQbow`x`^M}<?DDj!ycSWEqJ3y~tb_&qBO{??^mKt<pJ31bh2hrTf'
    b'jk7S+th6z<v5&3hV$rM+!{Kc?+RA#p^;T;oQM(S)M|UXZDt^SXVT^<>U_<gxW7l=%DFD1FoW{L)ZuezV>2}Qf{wtEOX1LxC4+RUA'
    b';Ia1=C9yEaW|@HNez`oql;4H6Jvh-ba^Gto*3$_gtqVEptnXV~+63Evwc6eGd)M@r2LQUgS6BkK#<svmD%2CtXh-i9uZcf#AY>Yk'
    b'KBrj|awNH@Ov^L}(>otVo`_Q6cTd(UF2x=G>b?_Zv#Bu3xeQ*;oy{>h-fq~}zYU(Iic!DMOKxtB56fw7PeKCYV|K99WHQAr`My4O'
    b'@?|Chs|So}`CvwtulENl@trHanBa%U6{|C0elo)95k`cm>JBCgXSS1rjXF9*uZOZNCb2%dzOvssEZ%g$Lc8LS9o0*UG>1@8MyGp?'
    b'v5t`WoWoxaq)8KP3ajUMc5ucVU~W=tPb|kAc?fXvN{TBwmQ#2ne1*Vzf8_S4vWr5*;PTrE3`6+v%d?RyfhM)y68!e@Vide^cfs5}'
    b'acR6zTXb$4)Lhj^t>$>~Nm{Ee)1t3C$-H{X?3Jv<WmIV}!_uyQ>g&QuXeO<zrI)U{xDRue>2=FoTSR|*53<#0o3KfQZV$o?M~W~T'
    b'2HNS6Rgbv2M5$4j`uolEepT9`SH)=W4U)ZxXQO=2@96ioa-3>LuZd$I@F5cL(dW-Di=qn2e@DZ_?<B3pE&t_~iFv6vI)kdaR)DcF'
    b'ssVmyT`$o~evAon0^?bw{Sc|WGq|50dR5Qr%LARrMMUlwu7eL+u^vDL@s4Gk#+wvxYM|4NfMQfacIKw}79qdv{9y%b{<O<7*9p4w'
    b'NplPjt|Cy+KHc7#^nk(S8npAcQ}*_<qI$>2Fm^la-SMcTcb5*BjEDYU+~thfveSDGlHJ@C&uezPd@SG)eys_3BqGXhJ%xK;dMH?b'
    b'SWC@2^dMZXH&p0A#z~>M2|C0geq^M2%pm#I;al-%5w~*j4!YKG_jnHof58Cg#(4M2(p{p#hiZoJCv(}{^w;HJUPCqybNiP|;jmT#'
    b'z*2{S9p_MF%g0`)tZ6z+_CsJ<>1||9JwnVAA32sppBp3XHT;gcIG;B5G>kp6$=CnS{89qRa(HjWGiF^=nqn5UwQOC21;hZHU;c3K'
    b'-2gx9@YQWURlZh@UrrvE7l-?TNJs`7zm6xo_c~oJlS_GZVH(?0)GxI%%4jg}9%+^#RaN%GX}wJuUD%gFjG@lze&nP6Y@mZzvtQDF'
    b'>ke8Wa?20QUd@K3(f!ypzY<7(@F#XJR8ct8(a~vjuhzm-(>m@~dfpa~yQv>VNXrW^Y>jx@#$c&fcT+TW-w@yJhIyJZ_v?gt(3d)D'
    b'C=&FWQ^@h<qKbzT2aOL-XXM3Y_%PGXHq@_7%8anb{Im8v%<Q$&pF!*LvvJDjoA!x`%e@ICjsR-^`rwuQ09f#wU{m!h%<r~+5B54-'
    b'!x~b}na}^;tGjCy6z#BxoN>NXZpB^mB`012o~_x}IEwmdXOPPa;Z-v9aW57=E|Qc#b?l5^FeT#M%G#R00(CQzmxzy6imhdoHSC$n'
    b'P6|7Hu@m-mJ4JqLqjPj}w~lo6wC~R?#b%QHOix}<{jzs@&DvJo+nv>Og#{4CM5jziFke&xvqFbXMJX(_-ThEsl<NDk7`iR_bJhsr'
    b'C8NcUKD>Qa(72@8HUGc+90tvI9s@!u0~STi2el2yBi+R&M#sDD@-;skLRgq@9wls1J#B+lHxdMmyH993@ZB;rz2x}L8jC4Xza(!7'
    b'ufCV|gwF>C1)9b4HztCo;?GyQ%|UA~aK^6U=Vsuq9_0f5S;8Q-**1qy!~nsdHyuy~chrkV+%_$6VV$K*bES0v_s23`mKDVU*399q'
    b'#ie`Da(uL%wz`BGYv=u8F)aO8AIA4<w!4DsC*^VWnKj@>Wz2}PHRO+tR!8c5wbwO<lSy+(>|c}T1TSm?=oCBY`GHigE%|=<+KW67'
    b'{rFTx+I<AiL(b-}OXV<*A1S)<uhMVrhM=J21KOcs7(HGsmhdiVOm~9`7?hep57~E5$FJWwr<eUm%v<}~<8U4Ko93`3zJw*UlO1yQ'
    b'(GGKue&3I+$xPWja2pt35G|0a{iWpf-_xJ3bZeL9B!ZoAwu&3#ePy-T{r=|W(%SPbkPrjuT0Sk)evJ6ItAcsMLQfa51IBEoSn3JO'
    b'uo?rd7i6*ul0$OFx6*?agsx@N?!{SXsk3L3KP(V`?535HSD9dHS7>f~l3L0~`kpCB`P`=aeD+jZS5uQd#K=!xnN8xG4;ile8_F59'
    b'z7BmC$FJAKV5ePsP%a(YqwX>z*|O@R3Va=$+aLCqgB|j+1Ob6fS<;891%;l1KRa9Zx|csYrA|*OH=b-L4y}IMZZA_kYk>rM^d1hd'
    b'Re~ziD7#ih&-p=kO4FJz42cmue6ZEDGg>YywrM+LTK{S63WJ<*YFb%XE0aCPu5s@^`^2GIPbBK#<mC%l9czS{>fKQw^9H!yrTz4='
    b'Ga7h|9d4-o-poR1-0jg|v8=&-4!Q5+&?cBod)<|-(ulIapZ}V<&VzwDbc=hIc_FY{=m4dMb||TxX|dd`W`#27%9K^e5u3%wz@oS#'
    b'ny$g2OA{_Gc68i3#CS8Z@ZB415Y~j)inkZNcbX-I9!N!WTn6G_JT&Xa&&iSW)$@7xt3d5$8Ldt0UV1Fhmaq->+s`VU%)-^(f|Xhq'
    b'y9`+t(%!Xcy;&XGZGpP<!`uBa-|p)TYeHYO!f;}5gmFxww;BwFlEwUTL|zAt{Y5n3!UAyyW<9cZt|$GRH~IQ;ysC|dT-eXxcA>(F'
    b'4f3nhrn|6ot>DtWG$`L#6o48n5SmVP|CNqDIav!D=k-(iB0f~0(qd=OfBo{kq%~RW5`8r(JwL;;E$%GsDRR_?CWa_jSx4$ii;m1}'
    b'3ghLd&`GOOueROBSI4PVR`!+3?YJBeM|!eu5?LHWoxycZhy%Dbsx9esWdrYB@3$`{w04Uqsilrj7Q04)1y7i8ZO`wc*{9FKcpGiV'
    b'gGv_&avZ+jG-nfvMXOC^gVUKKOU>Qgv??84<d)mVrgd2-nSX1#SF_=V>Ab|(`2_|zzxivsK)lUiRZ5vr;O>xtOF=bk*`<cmeu(V}'
    b'_X8)v;9f=>Zo#lBGN(g_x+*IjydXWspLFPPdh?Nkv(K^3xG#8pr>gg(J+sG!0!<D;W+~9W*qbbyckZxpK$N;23XB6+`IQlbx>jzq'
    b'wki;eE2^`c%z1`<Ln?+9N2lQdc{8iYl)DY0>X}tVnuTw(OOs^4@kn5r2_jH{RVdLNPc1YXB>c<42KH0~pY{7nw%<d8KY!>6MV339'
    b'UVrKezI}f7`eNyf7Tyuws{J>9&-igQ<w^qaS$n6h{rQfW2~pL?3rI$&LY-$PZIEkE?6>Urd!w?Tr<4DB2ckDifUaOP8l6E-KzHmF'
    b'T}u$C&27-Wp<1+=p2wHQ=w8o3KS9>yx{f_I!}?t-XwFdH+Q&j1HgZ&GVEt}=A5Rw+*fXIa*4i!C&0c~=!Eap;Z&b7C=Qu>v)LSqX'
    b'1bG@#o?t5}z})cBU$m#wRyuLykA7(Yygxy)<z{%gUbc)nHI?f^tP&^KKAeijdrZ-d3tnlXY!ZK_t=`TxRwI=8#d+9;+MtnR?<yl&'
    b'%K?1e=4Z}R$Hth*-}(5BrS|ybvb@}P#25icv;>Qc__wI8ZLp1elt2kNfz^U!?4k|QdaoxvMMsKk|FV0;hP77-=I3F@vu;Wc5c4KY'
    b'WVzT_X?MA}b%=w~+H6mh#Eddg>pu8_UC}P_P>UK-kBgY^m@Y0atHTn1o*M%GZOhBCcE?S{yS3*%dyOp?Hte5jn|nv={`SB?)lX5A'
    b'+*T;?+V#^q&7^i~-58;KgnhE(SK5>M@%9#8y*o|Craz#|m9lJcgO-^gChly++mjD7_~}cCeycWX=BDZrrTVtQ5@mlm^-B2u$I{Rp'
    b'rje+5^O}9Epq%z+mkF<NS{I3DiA&CU@1a23K?^$X@imG>`K7t#8c3}{gZr5_(D-e5<rI@xh0n<b%{S(AP0lzPrkazE^?<ge`SzDv'
    b'PR0tqPILz^g~#OG>YcAUy|-E3o!qEB{MvD_)oz_Kd-^J|;moYAy%vOJwW(6HXDNOvZrr@H;q-uKE$gx6cI-XdEo}M19djTnjv1gr'
    b'j{loy1NjEu%boGHI;(iZ;q&e^mZIQQx9|KWhU}$g1->s$Rwd2Nb8nhmZNIR&CflHXEKiuO%V6&|1jn}%=60#Avf~JH5OV5bdIyi)'
    b'M!vWVfA7^#U)1bwmmWjARU4RCD6d}GqDZ!%Xsv_N37>^k`3R>&!=wT8c?cWOvKjP|{@N0bwb~GSXuvFca?P!+&7t76eA1)FBzeY9'
    b'{{U+{Si%;+@kQ@Dv-ft;yH#d7{|O6*d=yiq{qeIE-#BhYM9jKOe?OYr?qG_ekGRkK^7wWZ<vK#0nn_1G=Ck_FnRgerqOsIKdon)T'
    b'lF+Qx)+*Rfik+AJ^RQ2gs}{EY3gLbJmcbNziO`G1&`o<X)SYt>!v0hh`~um&f%Qg6tTBG=Yz1s!9_;w5#CPRH+LNU?S{+WSO1dD>'
    b'(zUpm)05H|3wW%!Kz{oVZ`UJu1Bk6sU>SJz=~vl>&fB}$w($0>KEl@9{If>=y}Jh|N&R6jVgcWv!&c1U-LHXlcVj#|?UX)uA1zR<'
    b'wvsh~ior%<VG@g3YrN_x>@R07?TFacJ$f=`o@X>Bqs|nWW{zDEcxfAuyqpz;UY$JY8=c)2nkMgS#muJ#KVo(@pXVCbe0w3}au6J|'
    b'9-kkUT|24oi>_xMY;(-<i~8`lUv&S#M|u>WtC!HYki36krEUE6Oj?C~zN4Ek!JF#w+IqN?LwT|y+1h$m=O)+AyLGu;2Wsx6?(L(;'
    b'vt4UJ;B6f+glyql5aY8vCB&*}ex2ar$I{ASR*_iO1F0_3FcS1$&Ng+~*GtGQH|r^(W>HKJId)1TWqA#$r9i18w*s~Cib#K|&6eF0'
    b'k{q6ciw{xl(`m{?Vh^1s^SimuXY1Km>-}MEkZ2H}M>1CvmClB*NmC)im1@3gV=|;ZZWn=HP;iP8WitIN!)gV%w%BfYJl|wUX;sNC'
    b'*SI%L4z)RtLRr=!rShWEh1cVgb&SYut8=u#pHFe#&^_%oh%0x2IjSrgYT)m=f;wFhS~c$KejEc?7VOuD&T!FwVci<biDE-Iyp@p_'
    b'4}*ywZDi#{usYFOH`j4-&rK(hh*Y2V@sx$+{o?l1Y|R2>Z1I5w<bpFhKd&@#+ss>dyRs-0?AXfMNKNb)?v@tsuWsdtw7;E$F3{pf'
    b'6TECmnfHuqijxPuEEcLL73Whj+<eMGD{2Au-v4-`*y4Wc4s-r)Rr6j`F-5nJl$A3zAUMRVcdF;f<kq^!+-iAOBCeVqdc*=6temmU'
    b'TIHey)uZXcMZ4h|TMBlPjhNP|a~g4W0CV4GmAcJWnVyzb5%=HNTRM5ywC?O{1@lw9WrcU9dovqqP*YICI<F8Ivv<@WLaZYbD`sBq'
    b'$uTOFE4vjFpmM<`CZOjyr`chQTw%79J*}QPK=61fzw#q2A4uW9dF*DX#m?d*`skj6w0E2Ai?4BS6%S<ay6SC&Iln6!&(-Hvf^Cu!'
    b'2&5S<dsuUfX{Nu44($@$_^2NJ8aWRQ+8`xF_ik(JH4%B2C>Vi$)@HxFO@8liKH`*sUi)UMqnRU75<%IchU|sS9f`EY?&K*WQj<9!'
    b'!(nY1dw$uhw3j9E8>p!vUgak6>&zMZ&tfp`asd7u4N?t2;@1IGR0f5j`)@B+w&^S|JQj;htc$LKNx>g~wagkghXH(lADymyTjChE'
    b'xiMOu@V8yL%DV3j$nB{FTedK^-8$W|>2e#$v7A%-eNcZwM?4pndwyCbjt{C``K_CqkbCNypO^I1kyo{t2q3@emic#-%8ZnXLE$jD'
    b'q4|4ot~`&0YiUfP-mw~*&{7v^wXoXNgN*_4auXf(zuG|UUyUpN3?^gr4nW&>B}Z!9Z?C>y3yNrS_hP!>QK+$rQyEOXHZ8^?@>uRx'
    b'cr&<dZ<WyV3h)I^#<y3YPK9r$Q-)6CBuJ|eC3l4Ik&jN`<v3mBF?h^Lzpl11o|Vg0<Mx>SV${u=dK`c`{HBtc@;LCB4ipgIh)?ZG'
    b'!&i+I-TiD~jT?t!YjB&uLr<aW1)9&)2@N{JafGi_Lw)ZH>ShJ`=8hj=0R}>Aw*8%|7e#xqyflCF7v|nri?#RTP;jT2)^?7A5!ih&'
    b'SN7c8n7!aYHQHr$yGUlYc7J<9qw$Eo+{WWdZ?@;J*Yf)2yMTq>y6~v7?hjkFj<{qg)m#VF>e3(vXTSRMu;Oqmy;XB^rgEq<?hK56'
    b'nRXf@<D?|rMR7dLKcAD*oxS~Cop;?!A?kn?IX2aLs>@)Hj~W1STA~zTJlR@R=H0Gb+2Y40?>4v@lxLZ)t$sOk*ktO1dMavCKZovT'
    b';7lJXwq;!~W_G@8TF8(kJnRE}ZO7FsT|1|ABQ6XMLUvkqM_?~qbWGj>&CV{D_?0zv<^*!2JBvpB1D^Die0bKc&EFo*Yp&Pt7ci_U'
    b'Yl<UI2(k3%$C0(BrouBJ!Q)~!M6;&YZB8ACYgkw7aYn4`CM?vqh2d*H57aZVKErAy*~|;+^dMT>pm8w=M`hXJZU=!1e&Z`?(X&p`'
    b'hvd@j+($tD6YpR+3j%iCwumkxTf;zg*5}i%X9-9Ff{yKI{jw+WWQhx2B_m2jRbIMT#c8#hk8v8HNzE#!m%$AxAY1Y^KRl!1uMPWq'
    b'9(R$PcJ7N;3aY&*l6*D3G<*)J;Fv-&JQbi}iwOosuUdRAPOW4rUh4C5KOTz8V2rPWkxU$wMk^f$-=AkaYC7sctc}v<J?+5c;OEVW'
    b'Ng?q;fv4DJ{%NMi0fmbKMG=!;ueTcSi*=^awEX<V$M{!2P&0g_)M4v7-lwEnza^5dc+;k6?=G)q-k1%a?d?$J<I87OkA}^|zINd!'
    b'zZ}uvy?@O|pjl*2QoyH|RcBR+0cB9|D{z#A3zmGw9@$4sm+(fw0#zDb_iL<xw2gEA{mLih>#1OOkM8H<r#&zxW}E5>M8z{ReLji~'
    b'v}E9)ubkTLp`Dv;qVJRKY&~Fhi+x1u@5H+_6MfU^UT(e1;<#6p;cQwsv8^(oaTL<|j>cFxNcs2xwEeY)z0a*DSJh|Huz2d#lNOuW'
    b'x$ACI1x<c^!+&K%^xE0QdhuHLhUVshZ|zUfu3Sm(jd&G8gmmhSSQ8S47_cl|x3U;LHY@x6;!frZd>*LMS4QIf5k2Nwp$o5wWL_=-'
    b'WpFw`<}yD}*5$@;z4G<25RYk)Z8c}TNH+SN@~u|u%D%H%qP7seVDF8zQfSz9i?@=!?_JmU`1p`~7f-d-O>1FD8?e)wD-WL&`B)gd'
    b'2(hqM6z#O$^cvUsa{2R>%GjdM6@*vGqW!fYPzyRuPVs}pAJ0djV3pd_x>ah-$dkhr2gGR+(IvXntsELmDVpEP-gW`JRe#dU-1kmn'
    b'<U<{BY-*X9Uxn?=(9>7auYYY=x49vzNmXo*JfDvqP}B57n3UJY*1HY^L^ute?G0?2{{A!;B=>%y{ToA8;?te0qLoJr%k8B|Cdf#-'
    b'8hJlxOlpX4PYc7#>Q*l=o6X}S{q4D3)bUYi4kl?#HsiFmW!Bg(XwZb<mYI3836(jx++$oYJrKJsieh17cIr@!i)31rZzN6UhT?Wk'
    b'd;pcJH1wT%a&*!_a>jgP(UfkSrtI_geIo4O<<`J)BG&|WK@3?ZdRdh`h_$ze9*!Hw(sU*6v`g{mj7LnzFv|xLLdG39`@|P~d-Q!Q'
    b'C&m%;jcFaAdtPiKrh}CF_rcrkPO^AhUd7K}+|Y{SBpSDHD_o*8#!~G~lZLAOiFzR=RyB3jDK^&PhM}pa-nrg-9dvw0J%Hfa&Z0_A'
    b'Z{Of*Uh6ix#jn&%$9LLhA7_ByskTM?q*NcW@!NZl<?Pj!qeJq5Rv=1^XfbK+mQxCBooq+R6yzE$a6#<X%lj^NAy-aeJ+I80UmKO+'
    b'JF8F;!Cgv8YqE6LD!Jl-U@*XdCt7Gf{+5?bx;d}^^t^Dp5!)$rX(7mTr4K9SlK~=og^$Fx)@mT?=AmVwI=KugV^;}t2J!$iT5O93'
    b'`-09sJECnFEw`V>qDhZKEIP+^iR?#Nva33h*f^YrSL&xXpj&-HztH&!r~20*^p7P5mLKB*xOCdJUTrx(I^U|Z+st3J!>Kg<wDRdx'
    b'|J;dQ&xrN+w$dWW<hILa^Jz`@>&JsE48yhY0`UF@lU7-4JNSLy0fd-t{ImqxTAF2~je%Z$#p%Mv$IUCAO}x(sQ^&rzx*lFfzt-h$'
    b'z_LJZBdu`UVD8@7A4E~R3HJd=$=%l-oQZ`5aBKDMCsC@);G!60^_LfoAUAgff&?ouNCTQY;UzrHt3Ab8?$WrTcW)!)7>%2DIcMpw'
    b't-hBW*BE<A!%YY5syKQIv~VUwyV40XV_6?v0ODvh#$~NajmtD*chd&``}+X>z^KlrL5+fkCq1}Z>tq@CFMjJai>?<ewWfn_4_Ub6'
    b'u!TjPZP$dK<sI^*UjxR9seOR~@H&1fM63S%aF2pw{2to(D6RJSus<sbBeLXQe_Ax3UF(}tX=ot6Ts`&6tDAa<r`4`hu2)eWx~A2|'
    b'mJOxjrYo<H>rA>FJ{KC=om;o(srWguQ&pc6Pw!bjD+Q^`V}Xhv!}QXdluqZ;*V$Nu(H~Y-F<_*k&D3UgL*v9;CVf|kPn4fSid&g3'
    b'!jh$2TJhB(tEHL<EZc24nT~yuJ>Bts-5)kue!VoCUTUKv4!~_5?n?><eOR%U4cO75C#mP(egHlHsDXt<DKJw5RE&uVkR~GTY$x_S'
    b'tZxR|4lQu~5|Lh{NUFe(QLoeQji{_JYab}OK5<s4bF)DbX3#lUf@6Mjyzc0US+CAt7{2n;Q~dKOt|a<1qdWSj3-v%Zsfw#@XaU^!'
    b'qh@ftDTf=ktnCO0p!hIj4tzV>Pc6{saNQjDYv1lSAMch`exH=ivkP}^_@ra7`Q!TD)`3@nP9KCw{=WZZKbMty&>y$&jb}clv#YvT'
    b'ch*O+my=Qf(4}}vTQ@JO(I`{tF7ld6l4n+Ie)}Y+PvBMuDvk`c4+O|!>O8CQjHcD(b++C#@HGZ!boXW+Kc6yu<AnccmG}qk2%pGs'
    b'OXo|kz1NryK0vY*XpXJ(+3xOAvy^+-uwQss_Ks(z_gonjny<~iEc?CU?0$%@=IQ+?g$6v?)>R)Pl=kqk{=bR3j%H=GAoyD>l@chc'
    b'KoGG22})9wpn|wS1;vP%NT%QZ?%Vk7?v8t4PEYqt&#0Ec`Oj0~Wuuv{rp{we%w;Dp?xk<2%5RHRYA9VFaeu&JCX#bC-&A@xKkS}l'
    b'mbOgwN)3XE`SDvhU&gh@hFAfmed#g`CR<W(+%d5AP3l%n8&H+f&(Ee?#e_+mo!#B;c;KCm)$eh_pO^CawDGcHGTAk;D^h|i*(z!V'
    b'HNSn9!A@>DSG+u~wn}a(nhDDhvXA8i*ZBiRcdOG?w(bAHwCD`D5>K6eINy-`2{7aA`s#Fw<_2uly5!BsiM-ypeNNYDwlUwLHD;6M'
    b'ieH&5JM3+-<O5fAx~(0vZ$+QUs&xX(-NFEF6+bMcgD&UKp6sNe-*%Htf2#dzDMJEOjt=@l26<0Nl@s%_ruT_r3Pl<xu+J@u0rJH?'
    b'@y?!?B<(I65A;;-|K*PWTl3z{;9TS0WF9JfXx_wV%PlNn=xH43)FyU9beKbP|MQ9@uFBsWs^A|Q)jf^G70~IJkn^r>tsYhd!_8F_'
    b'*Oy_wZolshonCZXt&Er(qvl)vYEb7YXf@9+Ogi|?P8Dw4Y|f7H2~L4d?67-LCaBZDSx(nFtPpN>t(TNh{!IGXSi528c_>_V!~0u^'
    b'OJnlUUO$25`aQZ)_cJ`?!$N|}$B_t_a(v0^wm<9p4Gd|8aiK?0(o|_#8)J*4d_kGX3JQO{Y=Zu#dVA6<!00nwoKKG%H|x#nsaJ^+'
    b'XsV4r_?N1}>~q9H_sOBmINhgGH7@qnXf@4KQu*w?;i3Rj4V%^}tNbpp!D7_~|Hw;y?tNw=PA`9R0n>Z^c|nOvVM`9RK0ejaTO3}m'
    b'bYoF}b+5ssqBfr$^g)L=S{QL4id-kRe(hvj`#Yh0MKW~X6rEf+rS^Ua4=J$p?0{K_Y?fVOwVm0iJgNR>VW4A+{m_R$dD#$W-DV#e'
    b'loqmy)M<0bFUNz$bJt(bk@Si;MPzc2-bJ{$jT+NxHEj=9ZX4c`LzcFoE6#Tsc^R(>!}F(T$;$afsAWU)5Blck$8NJ+<W+=8vX?EI'
    b'|91WPtor%`mj}>e<0_AO6trJ;ORF|He`_Q86+c^x_NA()ihkH2H6UnE%DDX)e$@feU6Yb~Y;8Ly!unF%xkOmfxB~rjN~LkDyl8I0'
    b'wl6ov>WS4w69Tg7Q?9*7#Flo&Nel$Mk~~Yrtf#<?KE@uKXAaD}gL>mhb-i81-JQFkn=;fguM#is*=%>`Exl1^3FNK6#q!UKCDGx7'
    b'MI^DtMC`D|b^&kKmPM~JFC|A+kZ%x9X8eY$X=^3YA{4I{4f%B$!fI7tt2q@Uz%@rcQ&W=PiBakn>+dq_)_UgMIvUoJ=co;v{Cs+9'
    b'>LZ(vk#U=-QQ??8o!9t^@V*R6=o>AOD-^pKG<S3Kru!^;#;(CD@VGPxORrJ&>VEUq;HCI8tT9pgn@4K|jKz&qchi%q*Ztr+Jdu?j'
    b'M!md@H20g;dV}W1>_zlyPrbZ2^D4Lg%ER950d)2;zm8g_6mx^iME!^{hTl(Lv_hhwT<W|)QgwyV+;OXw7J$-e^n6se=x8)J4%ce-'
    b'poCvekuP_*IG(JGAROk)=T~~3xu0#b+l`|oNA-mLp23Q7p?^!kJN)jrN3oJ?<aR>{7*oN4bXm;)B=(n+ws!28G<t7t_a#k+tNpcW'
    b'FNW;s^W*b`u;x|4GPd!$%+8L*Gh3)jOt?np(YMLdsxUwHVGeo;mEN=~b&TR+xKi`5x@^5Vy*W1(g4oWk&^5)d+F?8?52nt8W94IB'
    b'kBkefzl1gYtECL|SMZi5Jpp)Ze4Y=|)&nWJT)p)&mt+UC;<3*f!s64zQ%u@@n3y6p*2$Bn12w~OcMqM6_*7QreF2K95jL0$Zwn=-'
    b'4AX36Ii+!B(tiKuvM1tkt+YqzyQgi)9V044uUfs_Z1fmZh*7j{bdEyctE;y%sEUxo9@3IqZEERWn6=(E)oAxxeJyyz+i5>Ku35rR'
    b'w6E5KNUH_2UUHJqW&L-*l$C3g^ip$S1o<SYy}7J_u1V2vzOLW#?YIie1yzErxZXFQ0bBd*?_=ELai$fD;vM;>%2zN$qfCPCv$~iv'
    b'GNb+}*si*p^H0dvfV^k@-r<eT@J96y2!UH#*!r|&wbwWGV05l%tRo$mxa>yo-P!AW*?QHZ-KmQd>TW$apI-$DAl=FGb%Jj8UL&j_'
    b'Xnt$_vVBq#C>yuw>lEB}R|NUfME*qRAo($@j<ydz>J5gweDx<ijy-<6JBb8PfA@=>cmMF*|Et#a*B#7_`QxLfPW>LL1UIEVBkxgV'
    b'C^ooD4R1cPj+h-v(eul@HLz5_X7}EYi)LM4MwUoB=!AIK;gD`E2)7@J?uCgAeA=TGt-iz+O_ar%SP6SK|GX%;&bQKA6XxuAJe7CI'
    b'f=Gf-aK@{^rrw#BvRa$o<=i;~lTSQV;&l6q`M{t+qD9KB+43>*E7#9kC-{&1hD2)@U;W6Rg`Gk~z_$3l6q8oB(XY{$=MhJza0>s?'
    b'd)YUZT79W<k5*^2H?|f)Bm>W_FIqk0x_{`O)vwoPO!21Ez4do5oT{F0b|}@s9-}JWZba%IciE23P3yTkji;!iuZR{HAK%+qbMAo`'
    b'py8|SzGlgLZ@MhMd*n^%QFhNlZ@W-kXXk@>jt^}4691kxd4mW6`>#%ZZ%@IIbKI;i-)todEk*4Enk})V=|~p&W_-gVlL<%jsMh|-'
    b'@bIc{QJJ+SrVQoUm3Z+6*SJj|;fk8`Z;mSC!eJQNo_zm#50qyOeugW)ODVVd+R~W8J;~ID)U0l1&GX^4keI>gG!mvW(fyRe5kE7@'
    b'OF~Emg3&iUK#U_LHBs#_Kq~SM!`1He?=D}B-b5#|s$5r=srl2e>~;D0UOW43%SL;4mqsGgmd}5$E@~Hrl|05vN)TMCv$&)NvA*_e'
    b'ctW>~W9$rOSYEa7`eY{ZZLMa{(#$#V*=55HX`EJ{U;G%1PJ&YNe*1{nkEB&uFj<_A*X=xSe{UNgdZvrFaY91`T=muuR>ha~u@9CW'
    b'a(d7Cinyw806_14tGzufH~OR~x6A&33ds8PQ8v$%oP7&XLD#yyg}FQT`(CN5lNLH5T-2_Y%M+tnUY*++a{tye;@*h8bwBl76EqDy'
    b'uN9&^_ZkQfl(3b8c;z>Gb((a~xMR<ieOitBoPDiQA*+!mdz6OW(J<~cn*Fz1?A&z$_^GH1Aj?TX`>^n+JS#Jojaqk@c7CnsHF%3M'
    b'P2y$Z@!6!?#zy;$htSPMT8}3+ST!z@jr8HYXNRV~Q*YWkJ%4Wd+8?F~YcF|9zx-8y{=GczB`@c%k8dr!3f=ny>3f2W-mrK$JH;Uq'
    b'E~Ae0muE{4>fxSIT)SlN{TZN>gLaI4arfj;Yps3JO{IM6=Kbcr+bk6DzE8QmXHMpqpEq?<6GWzv{_s-9nZAY)mGjWwfa8FH$!hg4'
    b'O(SOAU*#jl{&d8ygQ6wBaEI*c9%7(X;YRlIV_10YeQ+c>rMru}!?Q!QUhx?WN;+sd9YFv3=IXJ<nJ)7jLDNe0pe}aEs#>KQ!8(Jm'
    b'Td|slqia3LrLa8<b?`YH(_Xc<BLYm$*o{810%KCT^`|8xd7lQ16O~un>wq`^C>7hSmk<QDp1=98l6_iWT^Yr}2i){3FIMjbHg&o)'
    b'0no3FE35NWYVr;LaR?qf3EwZTWeMFdYVC6mCd*prb`WrgHJo}Gy(G_fZ4j;aewiPT#_@h^oyk8PF#Xj<OYQD*%X7O8i2+l)dC9H8'
    b'_EGsbq?UnWV6dcnxM01a@Cb47-p##XsUib2cJj=m#rZI_T`Cf7Hmo!s%_&pcnov5T^b}@bW2YZFt!LS9{Io+$hp+d}vm+3f>isC3'
    b'Yw~ULAeZ(e9Rue^F|fQ>Bf**+2XxYDN2i^EVm8RnVz&COL1*&l2B4~5|A=20vKX;8wdt5X;-j_yt{BAkkx_{D>q%+qUOrTB7XTzj'
    b'@VByAmD9;%ZTA~Y`%&jwnM5uTs>kVW`L2=e?V<4r#Oj_#_{7%YPjp>KkM@H0Nh>xd&u<$Tl<^mp+D+-j%+kfA-djz7y|%3ctWVv3'
    b'?Ynpc19~&O#6fe;?A^<tJ{=}V<FIIQw+~Oh@bchoBr}5_n3LW0t&PcX2Nce`I%y7Qk~>c=$F8F*yW_iBi$1UOI9%TP<K0Qtes$4e'
    b'r-t}=<t*KJ;$kR&EDcH{emAz+Kz@f;D)`gI*C<{!$_EA=?VQ@&6i)!|e;@cE@vhZZr}t0~PuE)^ta&w`<#8HA6V?RprfPA8{h1E`'
    b'?b11$-}C-8->JQG-NzQS(^4F5n@w-nG39Kt-hC_ky*;UI?P_EH1uI=H#)VlOg7)LHPg{pX+})h$>)`w93#eBQ4Z&zs3&<h!L&wQY'
    b'peOxmUprmxS5DBZ;pV!#{zzvtcP$=G3)H4JM~UDLIk}g3B0Q-a%9IobNY2p`#5{O=hsxQJAou0%JdCaFX;9%Jt%f4tu@1W>%9Q0v'
    b'|8N$czn;|c&??{a?j+o7>X`?S%jBIU_~F^%@0%i+?)(tB3<P*Rn{z>T|7bSYLp1thq)0ttv2id+fK^2lTz8XrHRc5!4yXHSQoR3i'
    b'E4t_|UZHQDfAzxyZ$R^zI>;q_c&&KH#t@ZOe_!-^nO(nOgFcY;GV_|`E3}b!a!Xx&x%Im;<Dj`9zScYMRS_M(JP)JJc(Rt@PW6vQ'
    b'_!sZiX<!R3Xz@+){SW7jKPW)!o%-8T>B|xyf<1jVcPW2W-D78SOOqd$yDG<9SlToZ#CMhHTn67ar>;x>>6ts@$Qm8VMNrtdu^L*j'
    b'{+9-1WOiESi~9b3&;2v;^TAFoc23R!_H1|J=+l&xlsV5XtvA9i&3v{zm)4KPvm`-lo<SbTLxx_5`&|<UTz!rk0#O1xchiK1scAif'
    b'bK$K&%HWL)w=;@yv2Uv0WB2=BISR*XzP<gd{N&Ss@yY$OP-f<3(bNtBOxoW~h=%uyQ<4j;)RO#<u70}N$v;KQOLNf2bMh;c%<-N$'
    b'DGgknYbspoW0O`KZ0(^?EB70=^5fVYaeDr?%B!SYH%D3Ilx)cgpIteL`lAXo?z~feF?9Gp5YoBHZO9CLvGVDAe7T3tma;z_ztG-6'
    b'#1jyjs^e=ZZUs9vKA;X+Y_!q7IUVcbZ^p-{=wl<8&+8W2F10HUOsFogBX8~P=8l<l#`yNqjgwrMWPo!=uC=B|zgYUCQNwi81g@RM'
    b'70c!mrGRgH;Q8gg81arjNKdFX+hRlSXEqo9X6POZwtQ-n1T#8|3!i#A6fK2=<^(&0Q)hl2Tt&4cidPAs-X(d42e<K>t8n)$uk6Mv'
    b'Ts#AyQ{^g$_i#|&_A9>Mf+t6$g!NbWON*%{3e=R}o{A74cyf;Q7r>KlU6a{Fra)TjPP^6dp#oKBi|n?h?VefCo|B?>Nmv{0#pL{A'
    b'VrjOoRM>8VKe**5v}Dv2+G6>ky%CF538?Mo+=9(Y*CG1zv^T=mx?RH3>hy5IQ$dVt<Eo-xZf7WdyZ^h-*BwG1H5j!&9?40#hF1B&'
    b'8d^XwA~QXBE{FEgQ2R4(4(2XkO)9x)#1E<4xKl~ii7=tu)_=VBu)(Dmb%X1tRddqQ@V3hTs4MMj_B)^4+s=a_izEoITEhIjtFRZp'
    b'iniLkj*r+juDFu8Y;dhOI`dhk{87<|8bGxtGdf<rNy4`4K?9=xc}1$zPsPKx?>dS`9jj=ALl)m2^VxUsYDQF0pAh(^ySV~@H-fY}'
    b'I9aT`ozvl>@Lm(!ROvzEB4%-9eIwn(8u1-m7az2VZaz&LGa>METLr*R>qTWPjnr3%zqrktdT!WI^wyNf1|MF>IOLq!(FTw2=@X93'
    b'T5#Dcc7crtf{rhx_3=2bAhXbx&~GLmFP+_bd|zedbK3%7j>p65d!)%__x0oRwfOi^!t#02DYQmmP@h5h>U@X(1THn#_wj`JdST^Y'
    b'!kC~^JgioGMaSxtVCL?`W8T<RN@g-^V5l>hG+G*_SN||q=%5^qdd}++Z@8z}|LqD^wu2#qvkPcw?~dklJIlN(IjyWO;Q({lJ5nKu'
    b'21ApD^Fhv0f*5n7!RP+K0i~YZst=t_21|F|OUW(eMt0LfQZU2BdS~<Z=iIwV+6DOKuay!^|1O@i8JueR9+utVvb2>h@6t?I$0fEx'
    b'2Ko9lUkcR$?zwmwMdsA{JuNA>_I%&Jzj1m^ZwJ*s?ZZr^7!zvU*hVSfTug}meFx#{tA6|8p%){y*0t!k(?8Y-5!0p1V!js=EM_!S'
    b'qg{O-ZB&1kAoPqhnbzldIF}Z4VZ!SZ6c}j76S_V6R#MX5aWuF*IrZg$)OSCv^-&dFRSw(Yy!t(hXX@Huu-RiD0!5DB4){bv(8%au'
    b'-JSyN-eGC17MtR3fJ>#*tio1yxKfz%$?4Mv-UPv<zME*nu>Y-nDmV*&PVs1epf7OqQfj}gGQZ{4$!{(o-}dWqxH&DWQdNxUX2F%E'
    b'F$P`=|L#=F_|p3}<7RG=?Mu?HQZkS`@Qji?NTZINY*t41QW{&)m__X^dzGFF@<~6ZOH8bX&|hjHdap_Lt1au)OJb|OwBsee#W2Qu'
    b'U}Ejpx9#tC<CGf<)%j6{iaHfvW(|&fQmg5GuV@1~NKcirCrOTU$lU{RFZ(-OGB(laC8o3SVw2z_qD4QQFCzVTujXaOVQdd~h!hj~'
    b'?zSx(>68ZHA?6%){rbGk%d=hKDOv%E>@ncmsSAG3BR0w_y}?Jm+!GFaG2r6uE?3_?p0^)EbFwUn4tQp-ptYM-h~Hi;DBK_{Cu^rd'
    b'yAEyuj`<kucIb0mk=g>JohW*OeYQCkt9H$8DClF}sk~hcl^vV}Q<dwCnyo87$*i{<<3~=o?Sg1t^noquwbqXk<*%*Z9_fA*K%?=|'
    b'JVAzhlmC!G*VPg;XkoGy4i{&0Deht#&`og9_0eOSCztZxtA+k^dHO)sC?cyz!`h$wy|`B>j{(G#oAa*#UR%lx(p%IH)aSo*NiTN^'
    b'Hq1SC>RAhptx2n0K5Mppf=Ql!pCDH6d0w91hvGa!H(I1muPI+14*Q$?rUkB}Wu(r?#0xCDJlu}t@RgE~TseEO_2#kZ{krdk#m{H{'
    b'{Q4PwlI=a@R2Dk0xs2-O>DZW$yX_%tATEHa7Ra9A-el}u%CmJ1`jh7qGRN;UEi`JBe|6x;PE_i{6oFi_tDi%G>y{rSUc7N5SF7>r'
    b'j~|L24qwK_>#|&)&kIJhl!4IDdil2ep|5r@@IReyy04r@2l8IqqPO6(J8C271dLB%mF)I=SZ23^s^7KDnfSeZm&G@3Znle0$x62Q'
    b'bGJ3xzno&-jZQ0l+EbG`0)*XX++B?5c>09B3U&nVc2>7<hi3*OR}mbsc7LZvug+#Yr`P-Xr`daOWL7S5a&w+ciB^&^4e#=KT9tG1'
    b'ch{Oa=q!&vopM1xu=Q|nN;X!puzlAXth#z@rxR-okfvC2hUkC^yNJG-3D+B8U>lyOlb5kNZ$$p{H8}`b>Zpyfsq+u*hIA;ln|3R`'
    b'&RHhd=>(QrbL_`O2O=SNg6GP2>gV-KIEfbe9W00KeWJSFvJTqw*|7_vcxvIGeKeOP;SZHLoe3Z4-ND<q@oc`yDB&@upE8P^GiGO_'
    b'Kow=uf?2VsZ&UI8tC{;1nQKfpb!1q}7S8<ii6a|`a%6upTi;`EKT69f&!Vm((Eh45t8~=U9@wt&Zi{AZ4=^7#)!?~3m&{f@WpIy<'
    b'RG9%b*hxU8Q!ZNec}V@Z%_)VhjGi<Svf^mVldetPxj;tG7?^%NDxPb->P{<1QG5vBjy2hWwQLeB0)ibciy7OL%=xgGIV{zfy^Bd}'
    b'fih7KeAALv@Q+UKP`!i)_+Kx3{9PJKKb#G)h9<8k9X=iFALnWG<lF7hYS%_D7l7J;w%G$W-<*pAu>gbjXwucEH#SwI>+L?@FN5x)'
    b'uV&(;Dov9*M)9{=k@3Ky;Us1=`1Mn2d?0n}X!D%|AzmH5?eb+gk{LVt%z6&BajNINDbDguNgYAn^EME@o|9@b=H%z*lXz9i_dVvv'
    b'n1?Ux)!jv-s=emxw0*A|{^|7`jTL<L^G9vARk}*wJ<|`b3NwlkIQ+`!7oXwx=BIM&@xvbaJbuCKI<CIYfshQk-L!d#53T17L&ZPM'
    b'-(68_da=N(hUq770)Q6GvN7g%=cQ#dPFE@Y&5f>(P3JQgURf=sFgubyYS<ZC-Q+4ly8jW`X$QW|G9gbpbE{U<1f~m5xx$@O0{^bd'
    b'V_+<u-DJ%4*8^NE_vY*FNxIiAixgRj)2xCa-A?DXZ#hewnL_?u${nvSF@N;kTnTmKKSje0)FH{hxp)1%_l6;k)2G{rZj<w6SpQ3='
    b'2K;KSQGaKmmkI5*_q3FScf`X#1*>#R`!dTR9e7iB)&8$HYH5qej>s)^a1%8tGg2eJG1d1Rgld<mUX+Gtlg%$iy6B$*9<u&UwAq|y'
    b'Qn8ii^zZ=3c^064GN}x+-0epjLY<B)`Rp3=G7-FJ1F5gRzr7;j^dP^vZ*W~THY?@mnWi7}<V9;AzeDjxg<U0__Q><7P)mI$nzxp7'
    b'UGG#=zJ1b)%QWtZ&m%+U-QC4zCV9^@rj?JDcl&*M1bCJ9xAwG^pHHt0GAlgZxyzBTKzC)HTPUmUpjS8rJD5=u-iMq!Maq@KA)9OF'
    b'YM9`Z*i7HRr~<FI*eF46$G=P?aKmoEJK{i?=W*8Z`%u}c#SP`d*<<m?5AP@~Etm%R7>JMDlSXn?{vK0RIPcT?NZor>Gz3Q?rAJQ-'
    b'vxCX4&Ol2KfYcnh;oVmmX6zlGwD!xQ@TC3-r189qUJrMqJsn&E^9`!@>9-5+x-`(oD>pC4=2IxFbzQ4YaglO-`km>8)vGd~Lr1St'
    b'C>q%@PeXtk*Ze98*OgZ}f+y;Fu&9B2KJ&0;-rj-o93AhMC7|_PcV17nw#pmh-(G$6?e%48$&T#HU?U#F(L$0A+E+U-s<kcz?xeo5'
    b'vzAjK;*3Epcz@P65Q>}z?A9-{QCFKjZu7K^&B=IcKmB8`=QAVA2`aZod3EX@9j+Nk#*at!9dKQ<OQ%29G-2P@rPHV61;S3*`7#M('
    b'mJ=Oga(|bc{Q80VUNowOJ9>EzW^+sTeBQEW01fW7L8~Qn$yRM1msa?0w0OW1KcDYEcQOusJF7>CZaIKSr>!cuE+#(Ve5)sEyip%Y'
    b'w0X+N?e^q$u0kcr@){vfY!@>HRPl1lVnz;bRt<uJPR)7zeIr35b}4wthmE_q+#ZtPed}a*r1SH^KIdtyB%30*Jm`bGkCYmT9dqu2'
    b'vs;&)s@kBAMW63NXWS)uL)zp(&~L3J)ICFZR}S!ZTVB0(jYSMt)O2G9h^fXe2~7@rB5utX|4OUG&!<;<EYGSO>JH!c_6fb|!PUd&'
    b'S>r|>HXBb>d3`BqBNz%-Q}_Ekc#NTrT;chR{YJaJ(6_~EGfVnPTKbCe&}e8xX%7$fyJTd=M%wWmKJ|ltd-ah&Rnh71U9oPi*DEVt'
    b'FDI3489gM<Mjv9e;rR_zK6|oV<INX3>o+^f$g&BK&jXPnYvO3wzxSwV6?q?8^nC3qW*%Kzywbeh*gAa&M-}krs~mNzZT)uY4AEkH'
    b'{v33qRl)Z*P@XBhdJSwLO!f$n#6|5IwP*6U!Alr0$T#`w!}e}%#4$WIacXYDnddcY)#IlRDjuiQE?`BX<#VTd&wskInb-A0MM~vt'
    b'#({K!P2Iu$oVf;twAF8C@*GL?ZK_M{aohkfX;QzQ_s*wgIFqIb2DTKeNpm62n+J0|e(si{**2%#-&^Rl#}avLZ3|}W{$isKOFo0{'
    b's>k$9xs%Fc!?lePhWCB%>5s-Hl0#RzHQ<Q|SwX!Dz)srO<uG1dpWH$D({`19_^Bq9Z3K^Dj1F~quU1VHt8^_AP3>><Sq$XyzuL0c'
    b'H6KUHZiQTAz2;*3vm*Dj4>F%p*log$w=vJqzOscN!9Sd$?`?2!TybYDo~Omuz7#}zT57MKUj)QU+_b;;w-mZQtzt*}^2EKxY4Fbj'
    b'1641ajzD~3j|Z;`NLAok$m(Fs^ccEgZf)k-bcSNIyCXgElwYdOq{PRI&>!|s)C~Nrebn_K=-~)!eB=zrIFd)<Yk=TS*(PbCJ>Y}I'
    b'&x-{<_H<bWd+V>XTbz&W(fE7e2Tf$d_RtN}V%Bq>TA%UZl*cWz^-0<|v^fDorJZv#bB~f3Y@!ta&JChBZ+!#-Rhi(@Dae&MTes}m'
    b';VCtL`=iQixkiuR>vi8Uj}KA>Pw$;CH>LgBoIH&)3)RkZdKEk&;r>8lQkkI5u)?}fcV2KIxYrZ#`Mj_rVb)d`a3QL6Dz83za~)^P'
    b'^LPE$Hx%@X`Rk@UyM@N3^p+$(hNBm-yQbsMCQN3N(Aq|OD-HU==GfPwxmgQ`MGwxz#;5gFo~*-KwC5PhBNg{9pcWu5F1s+9Qg^Hd'
    b'1U0s)_fT%jqd%YdQBR3Rvp(-B;{o78&#A8T-P(zqU)|Tle)Zea+J=Kp&fec_kJWGZQJ&fD>nBJZKJ^W;XZmfFJ8P!b>lPKmrIW*}'
    b'yBg<g)de#0$Ys;lub*Or`_&esI`Q!y8LbQMipY`dFC{91-JS+(QSsg%mONHCO=<{CZ{5k!JDrOVMjDzSMEMomPu)Ek)HS8Az@<YY'
    b'Bfjr^ve}cJfn~gQ!}jUNMMs~%69|XPf#<D@fZqsAVDe@dw_JPIQRMe=8re&J1MKoYStSoH*=)*rTVFLkLD(6i!`md<@7Pw@?mee{'
    b'y+WYeu~(5ou?R1&Py>N0b^h^r@N1T$1H1C4<*D=}cP$ElS4B_gw2R%9QHFmA6)Rg;sj5?8u)cM{Z|n{;%&|(15Zp0kv^IJiA34JM'
    b'Gz;~~CGcjz0=A>PL$0eHJSP{%Pk(j#-=@#mTQr#R-h<;tBM$I5KO-xLL8~@R)w$N)C?%Op7sKETFI#VX)-b?YgP8Dtq-k#**kc5m'
    b'g*zGc@Ym!5zokl4NZIUUeBalq`W+NMZ>rxH3{MZY)D0Jz;rpSC(A0n|2`><sJm?+I-=~-R9Y^c{pFieU;MsqC^Lk`sw|tbO?)cUC'
    b'5S4zhn78`gwa9mk$@T&-=go$+yw$oq{*``p?CPPpG^g_e_DxfDn75*xy7shjtZ@=`Gof1E$yN%yrF&uj+(QECg>8*>ZI5dDO`eD5'
    b'$xSLe+vqYG#}EG!7-|GhennNHeS5@etybK<XTMtIu^Z%YTltQ5k?poVT6mlElV?Ka9jiZE-S57*HfgtL!HG3(n&S;ni37mh->y|i'
    b'rTKUiHN#@I55w>+Cc8&F2nWLWwhWoA8Q;sVt5V$vKTmt(T6d2mfKC^s#cKaV2i-$-;$2-U2bZLWUmpda^ro#Y-Ks8Lu#H$s1Dqq4'
    b'$*n$6QGe10_zmXVR)fNZGWJ{Dpd{2(MTm-0TmZNjDddCr*I%wjLBD<Y4th{GK=9W&a+JoUaj~nsdM}s>ZovhGz$5c2oljwQcGe&#'
    b'a^Z*2KcKakH?a?F_6Rb^*Rk|oU1x}N-;E0#Xm_mY8XkRan;#dQNw>nPPRD*Fm2*pXJZsf@#V|l18`o|v<w_A<)40;sPR2c`RQE?O'
    b'*>B;j`N>;XW-1tPiMTm!q`z3%iy=h!x#Oy}h`SAeZpOXN4j<Rszxw>Nbt*N8E!@IhVi`bdo6}QBy+>F71JA*@JIOC|dDG$L@@HGI'
    b'1{TAU_q6*BF3*LY5RX?XJ*DsWNC>kH%dORcOkVxgXkNHW``Vb-(R~o6zgkM&^uZk%E;IoMS}=9e4q@UPaX1!+`#G?3v|DYzmnMT&'
    b'!0vn1!S@X=N*(9*Fh=7knwYYbgG{n+UG1HCsvG>^_-rxY?Ugk2KOWQtNB$Z3<;oRr4`}cV8CwLoEm=GaJ5qs0J4vaJ4_G=BCll1v'
    b'XSZFe??xxOG?$^~3>|vZ7%o7RSs#t#dR@0}qoKF1mg5yt!aQ`JK1suPO;~8VEVIA<*A!c=7Z*#RQ);;$tWhKRz{W0XXU9^<XboDB'
    b'f2gfS+ea?f8;*ncL%spjV$E<r-I1SP6vOnsMDKE)O^-)qD=@$w&9{nX_LmRh1!v}Dy8rD5D0<z*%lcalasSA<mpF<l<+n~Hr;82G'
    b'7YSE)do!j|t?f0;@DPtz_s8?FTe`2pOSRuP*7vp980gN~cTKM)<)b6wudaZ1?u*@(Fa{45d;DhGcTlOCImg8W6R-}|!G#@K*d6r-'
    b'V5#SEm&O-Iu-(?+Hrw@MTYntutCJo7or0;=$4lnbTf-ts`-{n(n06eP7yQQc@)`!=&fXP!<|)!b^y2`?V9zc~y~ACv9%kL%W7vQX'
    b'Q$1+zs(t5~fwc(-S$p^DK8->9OYkgiP3j9s$IFwkU9~=t(K;kB13aRvn53?!)bE=Itq!>DCfexH4!ghLpLee1vCT98Xew_@IMJgq'
    b'h;JHN1P*xSL9$uLoZBeB<LLnr*HC4)+g=yh``*W-wlEr$a7rroP9s7~(o`Oc;Tx@<-mgpDY+gnANge5%UKf%d9+Ds3!OykF^@MI4'
    b'*6`d4%lkW5{*Y1qiu2baQ>WP|oU1OZmz!fth4Z*I;p@@ux>{sDfg7X_QewnqW&BnnlWLptPw~uZS~Yrh!?0=-{r=81dwV_F`bY$_'
    b'BT7!^-uZ5Lwv_G6T)%RCe6jX2XlPUNdfIw@@4dEK=f2ONR=tT(;%AFSk-4i@V`en{YG16QV}hBAYH8ER&XeYGQHF2ozn;|P^Lm$_'
    b'<@aAq36I4H>{pLoqawcB%P&^$Ezh!+&LOvt$ADUT1m0YpPb*p59Eod3;L>L`ECWxvYEcU7#=z~=@2%zgA_JnwSG`co9FF?Z@AsrO'
    b'oB3Cpwc~pHh!?{((pPmcK*~jB-H9u3s*JjxBU%%|XfxU=o=Uq)Fy`t($h3oI$7;yaftj#;P&qWwv0bj;CdiBw_QM!Glk9e}@om8W'
    b'&BI2@Iou5w6TP8Gbr$Wje{7Ko?p1i=;)74eh~NQHz8-9$KDe>2R@U1c7{|!`Pm=3Sqh=O83h3#IN|2ojTraOyT^K@GcJ;z>J|?O('
    b'b|QZ>#Tlo`RV(@46)*pk^{U!>El2Q3p(Ww8uWrxqqXvdX-<gA>Qg|lt2<XF8CKaELK7?gkD4Sl=wJq$I!)9-T*3Y=RIWup(TD?Dz'
    b'5PyocUHo`dGgaXM@GK|G4UrLIG*uY|n9)}%0k)ESg89;S&3y0Q6?9ZEmV_00%gs)IN};}8)`}LMICiZj%;r6CiUcL47L;dFBNra('
    b'<u&sIW~V#IZ?*zBm$<>f#LkxW2g7;(m1YwMt@159TIz${*ZNkf>MMNQsQV7b)Ad-WHWJofG211;%nXfPPUXgSHh5p$o=bMHp>UG7'
    b'?6|qN*a=^&Udur3w}WfQ_U<!1R61a5h4}LE-0Z>Ek&fp#$p}1xowtF};X;2-CbyZQBE3y+x60uENx=89j2u!bN{n}7n;iF8e3nSX'
    b'3wq^n>-l}ua~qjhmv+go@8B-DSJ0eX84j36t>h_UbK>gp!Jo(^cf8fJ65p&hM$Jq%qG}l&Cvm^Ok`fBxrDM41@6v;ch5f3e<6RTD'
    b'mn$*cEjd^;@*!oSH8zTO;(oajn^QNx{TId)vJ0dSO2Q;>JFkK^KclS5<Acus9>;kIx_*H9=GGY8PDCR*PBrzEBcHt<J=fz@4311c'
    b'Oo9~6y~9Cfwjf!2#yW9eR+zi`#bN89Tg$P%nqqHRNKKqpE&Xn2c?xAC*ROQ$)4;2vuaXp+D`U)FZLicLeRr`_Ad6vjy4_L#*nF^z'
    b'^r9%aW?Z@vmu!78?9of*dxpq7vY&PUn=rEQs|UC`VxLzWuPnD5lI@g>*GN_ao)Zf`HiV_Rik@3~<*hsW$x~In7iAxA`H!?jDxH>R'
    b'qZ<>to$2lRoGkn_wJD@sGlhEhGawew52Nnv<U3{vy#(V_ZpcbS_oBXHE9ufnc9jR-DC5-0gfC|dt-fx=eMF!wsUK$tW2etL6v%Eu'
    b'x&t8Xw9%NZ8Y_h!ntOWvTt>;Lmtk|97T3R;d8-d{U8)}5o%1-7tZE*vD`q(&*0Vaap13dRjcA#)8JKfi6KKCYMg$p;o#E~LO^ER^'
    b'ug-KOuRogIBc29NuaybK%q-5c4n1$VU12R%sh_Ws*kAP~w>u=q*CyC11o)Q}!&g~9dQjtiiYGNTn>Ny1%=#jLn$^Xwl6;?1WxpH!'
    b'X)^1NNzr1-uKAfJw7^$4+95<QW{lW&IC}fXEoL8j_4BjAuh*ZP_&T_7*rvKD?Cj~%F^I~W;l)dG?}%2N?R3Tm=;pEC`l)j3Zm(W0'
    b'f!cofrwUKzrn5S4CQ%z6(OY-l2Ud0YqxY~rG8bZGD0%AN<^LD+`Mv4x=2WrTtc5Oc+m*WIqJ7H=?KDA3<3Qd`t5=jG?H$OzHegMK'
    b'=yO#knXns<NdnSHMHg?-{qWREC&82#^8JX!w17`bg$O+0k+J;MMI9D?oOjCU9!L)P_8yS?m<3RweKW0_2MBj-_Sz%E4Q+Q3RQW--'
    b'eq5Z&$63~Y+3<>>{U-fZI>})CIHUbJy6><zv2M9H|H*^~i;wMZegB)gv5CgyDV7j@1RQ45kWJf--g8z;s+U8=QrKdI=lO&9i*}I-'
    b'`xQxlxBJrLnR#^^?`q@z%h}E}poBlDO1dIZkO&@4!f;(=?8dG0ooS1o=C2MQ1zZFkgLl>mSLMUB#&;LrMgs1ixS!D7M5x$pDa>0K'
    b'uWZ6B4@Mb?QkVI9xbI8?9J_LIxYW?52JY6Xd_6<K?PV?=y0)M0c0IL2`-jf<*H3}kZyIR5W+f1BUYm98{HD-pTrsGH!tlfS<mRD}'
    b'wVLrQVuNf|<9qI*i(UH*gd5pgroow+oPe(h{Bf!E>;Vap*;}wkB~C8Q4g3yzE*OCNzwZTLQXR@WCHYF24d7F=oI$hvs-w(iF~pPl'
    b'>4uG{K5??wO|p4<9ncG3#_;nh!lp{XQxptzPX{mSwa8AEsSEOOD{rQB6FYQcB0q7ED*S4dS5;#%b$inJm|I_oV~3g03Wt@4fDT#j'
    b'Jlk=`x%7lT*UqV0MQyF5xIp-P1fjpWk=f$BL;}(rk$TsIHYr@{O7)U9+jRCPdh0;MaV{F~A7>*UBvc?WQLNfMFI!|ngD$p|kcN|T'
    b'>uVVHqyF?V;ro2I|0K}1b@5mAbc1x#(cB|<PE`)0$_LT5`?N{f1EISL4++w40`Tgpvtt^!k=5eo70K9@hF(Uwk;=gMj`WQ_z~5y`'
    b'oDCz1TDKmp^*EUd#D1bz7Qtw@B2K2WXdJEb*9!Z2Jnmi4&DHB1boHU<@L+sQaXDzFS6jC`K8ARof${4FK!E@DrMMZ{)2>zeT)Y#b'
    b'qS?(R%3M$c?o4*Wuy!<yu?sPu?N_S>=dIsRdZ!M8k}>@>XIp%?PdA%n;O4@Mf@OyKBePo1d@jOMgDRDgpEhsR>b8)yY7VH&&G!Hq'
    b'AQoBEKUsbO!qTuI$V7Gtjf)VB<r3d-%q#=J9Vj$8cYbGDT&$9NzTO*e_QBm}FLy3WW;Ma5_e2jJw#%zCS1f-z1&qq^5?(i1qPhz&'
    b'zy)9s+MOQB-U@sBpObsPGL^nryk*7e9v4gb9)kcf0!{KVnLGPCl&l|{p--XxgAIHdGx|x?j=lhVk-5hA`lMUyS-(Aj4sq}am)^92'
    b'KhXg)bYk7ibH2E#$kj+Nwet5*vRimu50mOJIQwa{uvo;j-`#a|7D_U5Yc!f!e_l-IsC}+GUlt`BI`xWH#-BV)%|B6}|6;>Yh=-8Z'
    b'M8`qP`eiz07qPugdNx+wt!W-FUkfy3YxRXXTV`W-cH1L1IiHlm3o+`k+zW=tCRWG&k4P@aOg<Otr25pvi#JTvbqJwT6aBZtzb8$0'
    b'sb~`8rc}b=GS#!*o8_hf%?-b%T(ld~Q-$69`s}y+Dkd~%y(PpV_lpnGDIl#)pn<KCv3$GF+10>1$3~|mQqyW=vF5xk|7AmH@oyF;'
    b'8iRlV9QLJVJE%?Hnn^M`ZCuLMokhQe6a-j+xE36_Q4c8VV2ufb)wS+C^U-SaVtl)%iti)y;85$CZ_L}Oj4OU^Ha#ix2iL*J^?Nh>'
    b')f`e$i8j#t!BOda87Shh#`|pLWqRf6YscJc&jD4YUS&6J8(DAaojW)lJv-tW(ubw~h9!CT1Fl(HxqeAwn+{giXIUo*e;)3y?x0$-'
    b'_TpvsZ*LE#WmLt^!Q-Ah)r1xr^At3h^_+EpZBou1NFD%Q{wOB&mu<@%?p5?U%MaP#9DzChed3HMggaEN*T>PI9V_t1)|jp6cbljC'
    b'TQ1e8jr{9>y*5X%_86AelQ{aOliT6oHO8koMr|r`BXd8S;T}%^05g$Idb!R5bJIVy#&>ubnFC;Ub^HE^NWg-GGO&=rGC#Sd?cKue'
    b'P)YyU3U$G2us^=BI~Y$BA^ms(%6(KL5OCg_3dpn5?x2@>gwmU#@{}iZeiTrqHO5CeIb^_lIhmR7`>H+cW`CJ|2wMH}e)kT&4?7RR'
    b'_q_AEX3+@%x(}+X{dyb^sF~k-<a;F4Nz*IpLDtx^o)4dETpw(#O7R%<G;+aqCs1SBKEC`GJ${v6gA?IKwRj@TJ1aypMHbLAGFu)z'
    b'i|dGyd&xqzOCMko4W8<69+u!JTdf`mGA~|cv2b0s7*)d_hq5)j&K3iMMIX?o_aW&(UuHMR4CCyy<g3iyDZB7^eW<mNbDWbMe3B-!'
    b'PkSg`>?fVyUOdz#JIZrFsy|Isb?U%uQqbt1jO{)bb#%4-Mrkk5rDS?(d#^p$uQbejrJQevH+Pl%rrGtbILx9TH=Whv^GHp*opbdz'
    b'U-_P{^c(lWe^2Ye9*QIp=yFXS{LS4wdy_S5mY2%aA^HW9hFf!)U-fRmogSrzR-QWfiy`FbG^H*1;gZ&|Qk$XOr8*2Ek=&QG^)eXk'
    b'gPU4bdl54)OIDt&sN+x{8Q40bYuIb_>+5k0Q56oZYw;9W`@X4Vs00Yb8ofJXuFl<fN~jG$-H-imuk?*8f6-rcnzQRV7>^#%+bX^i'
    b'+s|>55#ru88b4xL+Ysd~xq0W180KcFj<G+jw|n@Fql6(*9Tx`Nnl9b+owyCTFtKXVwH|yWk{XmpwL~3Unl!jkq6vWCl`5}kUssJ}'
    b'cRMV7PbRrBR;6+U{%DO=^^2+2+n(XxZ4UO+*{_Glg81~5H_=(?ZW>*fTv{8ensTjZCZ;e*DwY-;YfZXdc|5qsvHrMZsmiAN#U7`C'
    b'X{!Kl!4dm*OXJ}JQ=aP9e>PTK%Dc|G$f;tP>nN((zj-~P+561ax94&vS?^H~n9$vqSKebJtHC2i>H>}a4#^u>?6)^l_IMXs^^|<-'
    b'?&8F5pJo5LUvxpZIR$K;EiknlbKu-3tnrGhH!so-8A$T|cdp4j8M492)0iC|f7iFepK#qJrO{x3wO`32moCKQ)YxXRy&578y*xn4'
    b'-V7J=0x+;UUQd*IaW)G?S`9}!fZprpTK2v^71+634sN+=YheF!Wt#v8h*8B3a`k(-zaHD!)Sfx=cI|@;JXv7RU9BE7Jim-&ytN6)'
    b'KPAzE=KX>CKIQcE#!M@RUF{&qf_MjCfxLQ<o%D~Zwrazh7VhHPY9s%=-=o@O4T3!)&G5sct#lY-wzxRQTlFbyo4v<k>#jD#z^Hil'
    b'^VkEmQZIE_GQOk*c&sK}*>v#iyM>odmQ3aV`)DU|F$G?|UUF4g>O$(~X!P4F5)S!-?7gZP)L_BGdpao7T1V{6?hM;+f2o5EUI+HK'
    b'Vf>+ZW4!ou>gzQce@BoA8Thl>xu@8pJcfL)el%>Svfw1SokxBNylhCO^tyWzP5&@zzk`xmECfp#5`z^W1uKfs!frxx^W?#C_tULV'
    b'3Ips{<~_ii;Dy`6rsGOgrIz<F!q;+)?mEK|Ck8`yCw4pm)&+-+vB!<we_G^jSgf31kE6TmNQZTbRKn?90}qcUgMrstA_F26>_{j3'
    b'>iZj(DV6iyzbk_H2;G2qY@=ZTd4Um;lV!hmf|@r0y0v^Pj>hfNGHNN{0N*Jes5hR4|55g)U5hfwy72e&E4E8<qaM$~33Q<dDhT2{'
    b'>jx2;m3b0D{p~N-U_ITt_tX8Zs#SI03XzeK5m#K1WF~3F`K@7BtESMe9Gx1JQ&e?5e&*ioTlC(m^-WG`T@Q&lULv&yyBmgyCtY|!'
    b'mWp%AAxtz&J5WMO2(}rz7eDvNmN@GIx0_idoQ$&ip=4+?o(O^OGpSBAR<7l7F1ly%y^$>La;<u>u99U&<!lmqMX%GJJ>St{nc2Gc'
    b'q<fh8$O?TyQ<EgoJ}E}hc9qD;1{p4!=)Q>$%I#2}Ox`un*4c-)AZ4=jXPtTSIE-a>I6}BCU5X3^K$|?+iaH#?n_dYOr%8#9&LXMB'
    b'`IE}r5agD(FKJn}XIjHnr!qVwiN7l+c=a}c2Jl5sIm9Mtlvdicb~D3n^ZkwGooS;D#a|X6#GjZ<Ae|B7=&eSR#3AaNe)&?rHdLu0'
    b'O^zF0YPCWr&gNlBzdVZtyPa87QMi6DKeyAiz^_gbYYjAqrJ9#vqs(+`^tvApcHi281`SLYALo$57q_t>?6Yf?z_~8F5uY3t70T*6'
    b'56t6^maj{Aud|(jl~(h5AVAAMj34>@=*Gdu@LrjqmI>V!$2v|L{B0mtN)}-e*>f1QzI!>dqn>aXYycV^GLngqTFUoVZJ}r7-!)%x'
    b'+><ZFL&bU@O4JS0$1Vk4Lfzoh2}!;obE%!JYgcRf{0z~(ZGdcp+2pRxQGJ4i9o?YI;Ij4QQJa@?0P@nxL9+U~LR~BMtexDm@AFDq'
    b'ic@%&T#53NUyjQMhbeV^A9;Xr31vvE6;^7qRfn|-kAp;X+X+6aRob`urLQ9uaz7jr%;?=oSgF_hwgtrPCo!UTbaG0Et+nj~i)I#!'
    b'9=X?x++BO&O=ii&j+o2)`OIiFli!;7(gIukm9v>3@V=Ba7vg1hAA!LMnfTiY?~&eYtXIl2P+`|OeevCwy~c!iHz)4&m4T)&zEBg0'
    b'$*I(d%98zf95-HQRF<vw_O{yI){Q+)@g%NtU~ejoI!p^q`q6QZ?YS2ItdQ8Ek>M0)y>7@r69<OtLV0_Boq+E=z~c>`BD*mp8|Ez$'
    b'&VtTi53=2!z_tg&aSqP_%e;e7O>jC2{A}ea)(3F+Jj|3r4TOfvon8hm2dj=KLM?P^o5lL}vXv(Kut0<r4?xvvvgDt00(og$ngiWk'
    b'u||({^0Kb%i{0j2?y#44JD+s>&&OQ@Hql<Cm}fO!98QgGyR=_ENH{q!UY9PmI33SxC76kA2qTQr$(IRw<JjBTltfx!1b_Ed+@+I7'
    b'4ai%k(v#F71mry#u4~ygfbFLoG3`dR$|%ZXEZqlAbDT+ob^$aM1tb8uKz7>%h|&?%-}9RmpgELRpMVmQ!`fVH-^-)DTqxtn_jzTT'
    b'?S`S&z**u@vmZre0o`t=QxC8=mHYt62IuUs`CMOjLAc*yUX(X74iV?|TYVMOg*_O05lb7`{jsH??cF-zQ?ZHAyX<U=MeUQHJ3OB5'
    b'x7Gve!{S;v-GkyJjV6TwpWOWs8C_bX>Pa}hUY1(%>C9HGheOv3_Z0|-t)tdjR(j{=P~}ys)fJ&x_Od>kh9FM??36ikE0e)<v@A2%'
    b'Q6s2+$BRL$pffAw>k8OlySH8A(&!Mbb9AKF#d2kIN#|PDdVGw!JAE$}a=Xi6H#p?_?^A1dVO5gzx3lL;gNk8e{?1+B<B6EtnyY~W'
    b'Vqt$gPexhwdv4FjmX^Djw_0+-t`qnCVX!DD$KKq6nK@}~PTRByZa-=nqT-2{ehVH5>@%A?PfgkA=V_$MR3AI=v8&35zG)#o&j$Bk'
    b'X*SAYQp?(Mk%(e}`mW(*m#7zG1LL6Wa_6FRxb6YDG%cD=_SD&D%g<6W-*8j=Noh=b@-jFW-Ha_nE)DFLEIZ?E^2}zss!)U=Bcbni'
    b'Z<RY7>&SdBSM#*CxS5^u7dIFy_gcA>TM>6XR|NK-Bk=U$^$H2<?#x_!$q20LH{;|ypY^2Ct;;itnB@p}wU=BRdj|Fdp6@Hg;ig)r'
    b'LD?vS$0O;${lc3qWn8jX4M(T%xv8b{rUxK|jg$4<+}`&eO8p#fv!j<QpBs~vXloOv!0{7tTJ_sgaWR*b&&r4#?W_rYIp|v%p3H>Z'
    b'sDX>+yW9?GXH(-;IJ3$zw@Fl9uu1;A@5X<sg>ce4xCo=$GI%;2qASSMs*{Sr7K$f;dIb;d@+>cK>NP4aB|u}1_dF=9a#*h~U892t'
    b'F?|(u`*W7s)R6h?blk_S(fE+*=;f@^+hFAPyp+ZCCT104w40&zJF`*Wb1<tQ$<Ds@Y6RE{N7q}nwrkBR=$N$QXjpbJHUD`Bkw<o~'
    b'9e_Y+Zyi2R8C5@<9D7!CQGtWQK`vC|F?MRVW|#c;y=FF(yS6h-<CLH~x|(S=7(OD)r5Aqa@~j4TvyaUh6}E%tXit&HdE+G42fA_6'
    b'_Nd+IAXcul&cJYJM=dayU6*ZW*{SA&%UZwO$+Aby8Dd3!*8`L<YSp%;FO-hE-peYQmnxTiDFu8SmKSZe;&d`9&6ZGkhJgBPHP~dj'
    b'?9MtpAz6miHAokluUpTsgi*6Oo#z`M+Ny`wo_7X4>Rj(H_G0z)eTL|__tEY;*v`r#x6{$Sg*CWbW`^0ZHX7iWi_siw+8~@5hP3Ly'
    b'4^NDCBctem^bwlU<@#j=><`=AvPbP*4!%0jT)if@(!APQT5|pY7Ygd~yZ08Bk6zRW8ECCshxhz?^c<msXb!UXd}Xf4T6vip_r(TW'
    b'DF}Q&4ALYGV-vjZEx@ke$fq)#w9#7U9OUz6SAX1Jvw~D;VV=)ljtad$MApOn*5<;H>2q}nb-Ee9myLySh_kL02a~9W%3Q90MKrN-'
    b'%TLPYof|>9{+w2ifdoR~#wbm!2~?P7v`v`2?HANYOT+xK5^M^%bKYpk4D4#sAgg@$1r&`9cY!Z%cWH9TI=+bVa$Qx86*%lDv&tb0'
    b'&T2jUW?NE=ee<U^T&MGm%bmg5(>y9spfj(9V}1g|^M$sr`|sY#n!kBHpS#BGymSq3K^yv>6WAW&dIZ|Ju(50AC%qakOc&xvglMAF'
    b'XREGqJkHHhQg{}{>;Rh{@zI^2x2vw?JiDvI(3QcE3G0oOc+b*WC8t-ddjFcqP^zvS*(+MLS+(-5iE3>TOq0IR&Y)~%e3MQ4cBww|'
    b'L{>PhvyY)x<2F2)yA1AaGh58l)u|Y(#G_EUQfF{m_RcUjXWm<6EB4z7i=VJF(9>!SsAR4>m9!o85UsxNYnz9SE_<4SQ<|(V2con('
    b'WF9Hd<h4t5cECn6H_f1W3FFx%c3K?P<jN=z(PnpkQSBU9?PtzU#NE_8lNop`<2Pw2Z0_?&RJn^*Vn#~hR(SEdw>=a2{^<e<X|NOM'
    b'8MxQ*RmqY7#@s=(8DGjoI{z3g2Dug;l%COJ@bV1cY;ZUetn0IOA7L<;nUHOw7Z%pTYH&k``66^)KscIvZsBEoX^g+?9JDor8P9Rv'
    b'^MLCmatHJUajLIp9;sxYsIz~~%BxoQ?cCV|z+CGU1#J<Sd^`J;b4+NeZN;F8M3*gHP1)t>61C@0|IKPoX~I*j!s<ju4)Lv*i&1k|'
    b'5vC)@d<0Z+yQyORLf#hRv(zP37Jj$%v=Zzvu~yg}GpFSJkcJvlx;T%DYmeOb0^X0>^!!u|U3Nb|nA@D*dun+K%bbVy>b?-4E%!S|'
    b'WU%qNa$uWpv1y(hY}aW9qdc*_wz?I_o80f%nmrB%1(54D_bo*@HMsp^(Gr$LjBeAL5pXa<_B~;1%OiZ7`m1Gmd2e*`)Mmc#;U`!u'
    b'gyHymM(gP&Ft8rW4H>4KSS|VI>|MQ`iQx%D$Tv|i8(W*b_j=qwDOMZs{plZ#Bt9w+7@0oWPq$!q{he_pMe<c}(FROQC*fMi%w3^z'
    b'hQm#=1>NsHsdXU=YKfyjE4(sUUQf4G6&P9go~KB8pE=Doy<@xn<Ts5h9^Xb62O~4eHqf);LfeUX44}Fvm_FAl^>f!OGR=N+RYVfe'
    b'*FJRKgFZdWyTP}HEiALbf+}}w&A6S_*y3$D9qE&2qpwEibFtEr&J$NdM;CJCn;mj$Ae8ecuIk;6dE$_65Xr@Ci%_i*cFjWCHdtAe'
    b'mV*ZOHJj2}cq8KXcIC?tj}@ZR09A&<#!5pOn`x2X%C~TLn77|@32}yW8>u$$5O|`?*2QH!#K>hA8MNeMt-^HHpvueF;a$Ro1+!u)'
    b'e2zoSyxLlDL?*+{LU_E5t?wSyGTwuvo5fiU&`#*Oi&D4zePSqN(d4-&Fb#tBbkG$?%QoNBE#)CjZ|+cvOCaU9v&%fr#+A_u-Zg3!'
    b'#+m2HQ%G3c&N^VFW!}4AE|7X_e&-K^+HgykYLEU+UYov1ksdX{Zfv*Meb;v5*1W%@qZq-qXhvKxwF~Z6ud1Gz<Y{rNU1y68eHV1U'
    b'&mX3_u{5OY(5#p_;69p-lT0yU4=o^b{kDa}$3|%}t5b)lid~oe8d3`T!WJUr?u>d}s{j*ir{F*it!A-IvA``h8aILw=<=F6j<?m*'
    b'8faw4NV7NVBKhXXSH@fBy+KsUA{~7V2V$Yeetn+h1}w5=)G60<M4vbX87Mz38!xC6@6^e;f%=Hq$`L`kR$O-TK5PPood%O^gBCr='
    b'+ts4xC<l)aO71QyBC*+O5>vkvUj9-!XKM%9V~^iw9E&=>)`nOQJ3jWWO85AXwE@1|RZP$o28Uw?*qAwLy3se~Vpr)_ws?mUti44x'
    b'>t<8cV_QPt(9$uDv0l?nUTotcDJIaURG6IWosna$5Bcxh7a#kt^*J|P?vq-eHj@Xo^Kn<VDejFf$Yg^+%y4sdcO%W1?^DD#(m%n~'
    b'KKDg&%hrJAh<o<dRlhRp5L<0KIC_wUUF$M_8(OuN)UUyt_=~+87>Q$hoDvpEb@^%Wv>k4PT&WwiDzV*#T4LLmi;rGmW>VL>Ls@A7'
    b'@jAYcZs!8<4N)$v?<RCYO0|TY7D|H}J3085buCNiO6^MIlOCM$zI+~0SCJbpaG`7>+vjd`K-@)6&dl{`?&3*zV3I2;l3WnaQyRTQ'
    b'^%b5yYdW`e%yt&+T`0ASXN3cPldW)05lnrlxBa`B8LpoRXta#s_MBe&t%;QLmD!bQ7t3KYrd)t}EdnQ-2ftsazfPH8)!nd>JeqI2'
    b'XS|Vb%f(Sv+ZTknxdJM*J~b*8DsF|hZ4?X!D`PXVfOcPGtX@V(=A3_mUQ_;SL;9{}FHXI?u=9K4Suhs)hu=73$YlX8q29r8xz?@y'
    b'Tq@QwQe={!bDdm^a99%a+r{9`N3(z@-{+7mC%qZnTMn;oU(zd4@39$P41ki?r0~rt<{aEQW8_pXXR>(^B^#G+TgXjzQ)=R$mt@1>'
    b'J<rzx^}1v#G=3aSbzt-8J4@ZI73=b|AhQZ#o>~nn(?+R)VTwG!w{)m>ijE!Ua!y>g_MIal7qPT}=8YVRba&&$#wLs{k<A<1E54kS'
    b'KRbz3y4peBh%)Q)^^3Q<S2Dfl;eLk!&KhLs@@XvlP)Z^Z=+0nab@#RhS}$k7dqQdIV*~YCUz}eb6rjjDnbJuddW!<Bx3Q;~53Bde'
    b'ZlK<`$a{e8PR(n_sMvihRGZUj<h;=3ZN4G^?b4r0kK*(Zl=N27ahzJq9ql_u-tSAV{Y*qTLBHhf@4Byty}ee>ivuqnVsv2MR@@-3'
    b'QuAQ`cuob#Y6n{YaaU|LOR0_dsZ)Kx6iyxT8!S;qv3_W@i-jKSBUvlqt8kd9mrf@CJfD>vWC;GyFtJSa%dvCtENN>P83hF0JHJl}'
    b'ZiJ8edj=HS{Y|vThdPcmrlX2AWmZ>WbKS8MxZAfHw)=kB)&7CYS(~2RUe{(&quXM3vTDH3op@`x@KwsiO^TU+&yP}sSz;5|mTV62'
    b'JRfn#&66HNyU{Y2E$i&zG%XHel3AX_`a2`dE<8{jNN)(5?dO+TkaPWMH_C@-S)TN68npM`5A#BlmWkOUk^^?#Lvh*va#81ae6ez='
    b'JVu~Qxs{KI_Ypr$s2H%6P>g^veT?!``mm;D4`gH)o-YM+OE7yl4s@}XTtenLzLXCusi!69$*uMz6Gs{dlHaM^Y#q~cGw>T<?Tnr5'
    b'D|aonggMAOENC)e(bPP<?1Ee?wxx$qvv4k5+Vj`6oLf_UNout<Cx>*}>`jcURYnajD+Vrzxe-9;YTMOjdNt|O#u#QX=lW>0H0aOX'
    b'iXjnQny+``q2+Yj1q!!~e5}|*3*6j8p1C6P^RN##-4d{R91@i;L*3i%!AA9_X4*C`jEGaUb=|GX3JlX`WbC8&V$H#4Y<=q{^E6U}'
    b'FCHqOiH-Al&c7m)-8w&ErB<OcI4?}%EvyXsjJNh~OpLn67!+DwpO4$1*dX{E+W|_eXqdSTCYEnbVfDIN4vNhQS1)o7)Zw(|CO4bc'
    b'cL|$(*AZ#^NZK?jkGJ8h;X}!U^(5Q_hoDB?3c?v2_VHf$LfI2IFFLdUz~eJAAP@6dpML3l5#G!74yNGU9CdnOZDJHayveO5l|@by'
    b'U8)*h#i<JZsm=8k7j{<7jbF&{De<c?rC`(Qr(CRUqdUfg4@=IcOn5VE<~e;|=~XU*Za^z&183fo@^Ttg)pD&`*{Cz3nkJQ3o|&Q@'
    b')5L%iyAt|(efxcOv!uI-MprjB%wE}9F-rh5r0{;J3izfqeLc)ab@6DJ)wOVYi<+8cbqzUpdj=UxVx~G~0N{CSTTF+e&xf>LR{FW+'
    b'Gt$%qvTs*T(P|@;`R-5QpejE{r+Qakcdrj|7yum(j^j9qk@7WIqhMU9dfN&aW8(Uv4TMR2-r)UXt_0kV`SGC1#3OYl%w=a*?G<QI'
    b'nlDD;L9c0$qTF^2W%1Y7_dRsMJ`W!@V3lY>_xzNrJPr^OiAr-r81K67?WfJx$&T1uB`Q=fs&)i{cDtRx<M3FUITM+;@`rh?jK1={'
    b'$iiBpaZoN9XgGr47dy6QRj$7+e9y!PIWlN#Is`qi6q!A_Efj&UyXT}_@jeHgAq$4n#HhWdJzCGI6!ch%0Df@D>q)iMJgH47i@Ogd'
    b'6+T&Ww#|fP1AV)QT&>X%)x=9=w#t6@f2GCFxpkXU;o-3D8K)$nch1s$9oD?_Y*~I)OHBPB-gZ-92zJgrXqOCnizg)3>qBCTSF}5E'
    b'QRyP;z47f*PdeD`GAC?x->kOOVMkdv8w2RuuVbf<*S1I!)Y`SMs}yVkxGl3OE7RsyNVFG|?pwz#7q_fC;^TxUc8SO6K1fsBb)znz'
    b'9$HXHl<Z1t@_;pI7VxGuS6mCSf!z=89F&mB^viqw9MPT}4nVD4;NXR(YYtSI70=0$ny8&sRhv|u$~Bqxa%8t8bf<>nW}UVFK0h^N'
    b'(`-_wMI@BBNt+s3Y32IxL+ISEtS%d%OhqkEqWQOb{$lTBu60%JDbqNNpO7l(!jtuRSse4mVhJo<KV$6pT|sKq%U3h22v^*$0JRJ?'
    b'uGEYIsBW{}AbxQKX5?<v<9(WoO_0v=7NI!@XWxHCJ5O-GYdCXDa)TWQ(|#FR6XyQzlH72pDMR(3pGO(0XCI$6-&~&n{CKUax|Dlw'
    b'p3OTE^p4H=)UK~;+x@UrCF6WodlVjy*ee}S5hvxyOC6(EVcJ)i_{)BxJh)#vE2Bgt6(6yE;8t@OYBH%c#7cy4y~nsG2d}<YNcLu{'
    b'W0#v^bDTTzdOPE++3964Z=o|O88OXO`+40RTh2+>?sK3NZXm8Q66>e$JobSH9At5;M`$}S4>w5hmN2a*yL(|?oIk4Z_B~V9BTe?~'
    b'7CUpI!T4o}%l?2Ia9x+eUqLzF8U|6w%#H^?t_q=M9(QtiR34#jxM<D}J^as_ijzppEI17qe;nRpL7I+<Vq>pdHmEtwZZg!4=b(Jy'
    b'GFZTy0%|c%9$Jr!DAZp~2TiRtC$*XlwuvH_%|1(bH~+dn@Y#B(WHakJY3nU~f6so`V<+m$4z!8fe1I`hT05097*!q_85rIQnIUnm'
    b'd8}6M_NadO8g~tmk9Yoj>OP`0&d!77n<ZFd*rLms8s2d?CqRAx{2^2Tdp+ghsk~b@ipaNKE<sH1;FRb^OGL8o>8_eGm>Dg3U61Nl'
    b'(TQ?zir8E<U}M^-^t!#o%(iK~SKKG0@2$3k(Q?u1V0OyZT)|i!mql#2ap28-sB!VARw@<Gc<q~)kr!SqXU4<#+b?GOs3Fu285}&f'
    b'okx#Ri9QJz*ON*8GEs$R-;Y`7&ea4TW^yaKmgPZF!7a2%MD;>6$qs2Je(%q-u)qa5)aj}u*C-vh(YLPLzM35b?an>8<t`p+-4tUb'
    b'VjUV<u5SdXecU6#yl?RPG#a(&92>t*)93sK0%f(-YZCNgKX{3xO$K|2*)QKpSYDoXV!5SAy*vA62DCoQeb+j!GM#CQ+mK*CqHPQ;'
    b'Su+W5hUPTecqdVx0&H~M!=?p>pq|<$P^2z2MT4_K6$_(I;bK}<v9Rgs=tSRRy?8ooZQe=YCa{-AAYo-gYL=$hch0;G<I8qt>B-A{'
    b'tL!GT0t0I1`Z8Enm#z0p*u4X-#5u1@iRfV^sAVEzwqWQ5_hdO{O;V!;&_VFyE+^UrxsD2PPkO<#K5^=;dscsCPfz0ZyB>RFk-6*!'
    b'-2!Jo?yMHc^<tvUW<wI_L4UGugC2F#&YSqaWKtS4o%@Bfsx4u!d19>_lH4d8?zp?94vhkL?>j-QcMl{bY(m9zb6XRZJ1X$wuMM5t'
    b'P;Ng~AR_DbVE%~h%p&Np<Ux_|$Ky`JO2uvjFpFefWmf%Ohr?wV28Fsf&!(W^$bBIVn2C~K6<dB?xE$h+sg_HV)o_Nio^gpPS&i}f'
    b'cU$O{T*6gk!?gL)=s7(UTJdn*yTn9mB)wUCg}f?<z*YNxblb52-tBj+&COOG`+YuA`cUu6IhoC-(t0YyH9qEy8CvW3ewCO}Mts!X'
    b'6<ox>bIT#pZ%4it4ASgHJ7%X!5M85aG^)w5P}o<M;KiTE!YXc;4po6w3d3Gc%R9UN^QoZClU9!gW#bNYlis`DDL_q3OBQ6y=}-l3'
    b'#ZF@Rd>UuJbLMMm?w*?9)_X<ZN#9<#*TaH4xsQV6Fe{5`Er*9o3N6UxF*2T|FiiRHbh0&v<C=n$7;wmHz2$y+SVM7?p=Vy7g6_*X'
    b'P~7dKCO)+BIlY^F{g4v}FZGyfiE#!TzlIq92D5jpbrY)%`fBXgwf;=FY%$iI3Ym;nNC9KNdy;j2NaO6W-BL3HFPFWo>J7$nymrOi'
    b'AD@ce-J#u5Dc{dkT<eH_pD&x7tj)dBdTAY~<EbrplS1OF(^21d@!1YKUq`vMmsgMN2HU|Frf^R23}AYj8|E8Z1Rs#2QB|QYP|6O)'
    b'c{m`UOwegzwi+kqP2q^a-7J6Cz#y6B{5W@3u!-3wA|H}W!S{SFKrSh9LHm8YLmpLeuw8a?l`;5gX!CeCPb>dsua6m_|A=GWu4;|v'
    b'eOi6gcl3_C*=&DuSj1&K9E{P}NB`_6>OtXhy;q~op?U7L&||Q)S`+3yM?2U+-}dWMHNss)ysA<jIWjUj-fgmB5(Rq@+_G(INe(lJ'
    b'IeU%~%ud4h+L=GAaJ#o~^5mvk8~6*N1$>{~uol}DvgB=EHHybB+U>*wJxMm?EqaZQvsUxoyI!jFbQ3+>jvQvvjC$x6h*pk4o5Etn'
    b'Hv^7-&6bC413vBgL}?qJtR)KG*x5ec<$ytWCHr6OJ&Y>gWz8<yHD;e=3&+{$4H=JD=A7LR$XV(x>|<+e2)epsp?R!U?=`{VZJHae'
    b'UnKzP<u22QBO8jmx2~OpI^M)m{;o0dKw6O0lA4JRwey`b@4L0I7i5(A8*G-xnKNRx_wJY%FN85$SnF%<#86Wp!$yT8D5Ci!H{GC1'
    b'dAS02=lPDGfYS|G-)z}pQtxH$cL#C19My$F?Flrd$8D<XF8J0CTeOD}3;n^?@+OlK47S^T)|b)fm;<otagHkCQlyQFarAbJrbu$z'
    b'3(~iz{(gKyHut>maotw&ee1TcyclZ7>1wsuHM-B*%Q93#xH$XcL;t=rNSl<NE&;7@U6B@*TZi8m<M{n_&+_p;MjygGCdv+3#JrF<'
    b'_<jD!Sq$V)P!wgN#==#CU2M<y9adG5{L($-F6VG)Sy8a_^4k2+cJ%di{>8&<wYYu_dQf+hU5)9n0(vi@wx~Z?`!OuHAO7sRwvZvM'
    b'=yz!5Zy)EZP+fGG^LYj-E>?3|Vh}&Bge7NJCy1S!g1?DZ`AqKN(j%)nI-$V>`mRe^u4q74>B2QLrYL6^chB46`aN&RWBLVT_u%~r'
    b'O_^*_7PVq_+8ksv>Tos906Ts9oE+^HUM;n2<jk@Kobwpnoudb%q3tgBv4-N~z1KIV=68<BG^E!x2%o5>_O0oxmP7HX4rgR%btnO)'
    b'K9y2N-5_42ZL?tuBQ9LB9nto71hbHrDATX13JF9fV~~)!HX7bSl-cC6+c)1hm9d+I#YVI7-Tzg3((Pr}xMZ2AJ+2gH5oFYM1|IjT'
    b'XRXyjfnul=!)x@IPXLdo9^P#(W6#=!!edUN)Wp5oZk;ss>f=~D8s(J<?(N}q%xaeF^*s@Ij}O<ucTR8qqK_^6PHa>(KlW1IVX=)O'
    b'UCo6?TJYQjdOL)4?{<Dv^N>RbQms)q>u!zFA6lV%<qVXE?2>+w;yk*{tWIZ-Xgc64EVcG~-n2>Zp^rP?IrDn-GF0JkeKHg?q)T}>'
    b'nT%?Cr3`t8{Kg)hPN!BMIx8e^6yH|)CPR5!qpxg_5E|ixo)E)3@x(>5Erw_aj`9@Q9{Sr>%A0fR&jTE$K>^?Wdiy<_&&1ZaK$M=v'
    b'e$vDfUO*ZJSOrlxVMH2h?}v677|A_yf^heUI<;oCaChg1;}{kWd9VtyH<Aiq3HI)CgbtKaf>wkX;PY51Hz2WF^IKOo=(XHD3Y+sa'
    b'(O+Z8zY4L|%g~j2BzJj8&K~?O&JSKF@Vs7jUOhia+y*d);fJzvcj38l=n*Wuv8;+Zj{CPFa9GieA@(Ytfcjv0TlD?G;yaHW(`Mb{'
    b'R~Z6@%efohQ0@_fZ@>x-HP!rHqR@xd-*dO7I#t$<W{4C{hl#V1!#r&}aiu>~Dp~`g&zslHymfKIpDwG}!ny}Q!7)=lvdeMoeQToN'
    b')eUi!-r%D#&!!c}djeiCI)fIorEr}IKhx~pBS>VGW{#hd3G!Yth3gbqwa)KzKa&(U&0`H}k}TbxwMV5!(xRxdcR4JM{?=>z<xDyM'
    b'=Y90eR_ne-;{I4{moqb!exiUcQDX9}%%`>4VR(#b)hbO1Y-M<Ewl+yjczu{~SJJr#rREHO?&;Y8GJ-BpC);t3bV#vePOj6}MwqSu'
    b'<c6@s_ng3d>z3EXvsx<AB@?+&9`rZa#3!fagOu-s-Ut+$CHp#C)ykWzKJ7QCU8mC4Pi`Tk{lR#R&00$c)&z#ickTnz1RBJpH;GLh'
    b'9W$Oi5`!1|owwl-F38jdE?&9!*5C;PkV3|-7O_UquLk+Z9xobeqBpn|k_JAhr2Ma%us+)uQ&NqNy6~8su=zrH*V)%_ZRb`S%fc!u'
    b'@;3CE#o`O7?RLxHdnO@+UG=&YG&@`jy|CGYR6*^M3uxeUL<&_VQ$ynT_!vIX;(Q!UnLTif@>OM|IAc{?%=9rf>{RmnwqjTmq6vG9'
    b'&erw?GMG%wDjr31rG}5b92?nNPp7kAtzf6?lUHBZ5BA6LV!2FNFExtbRxK{}sqmIdN|jc<BOa?5SzZm6cUrG3MP@Z#Ip|@BuP4^C'
    b'_$;Xk99(ng49a9(a=K(*TBJX|wVv_7wvctx3(KhL&ev;Uj*0Ysv{O&(UT%#|UH*z2vt86tP}wey7Ds$oLNlYK(hshaYp)xSp0)^r'
    b'=2|=>O|YnzXG$Fb3TkFD2z2Xw&S~6tem-aqF=AEEX)b!fmkm&DHvvb~X2~XFHA>x(ZglRLB)Uii7}^L|5IGV*E{2l@bi2ea`cVgp'
    b'qVuX5W3;;|y0mfF-YL1GWrDVP%_*!nu;MQs#vNJf>~c9~uVFWZsnv0EJm+RPDz~6+@r=y&_gDfIoynzjGMq^%))aLr4lbjZu}!u)'
    b'FWi?6lL&K;eP)$%i%_-~w~jA?&A>3crn5y(`gd<&?Qk1M!wu0F@=B?}p80`(;RVs>HgKZah7=WNtT=(a^SoKP3LcX!l@49JrcC(Q'
    b'<?8*dJ2T5m4=?mD1I%tWPKPY^!ae^QinHSJKxF*Q_3InJUJQs0LYVbvhL;6R-r6;MTV_J-K0Pr=I7g5sBbL?hR$mc>>{G_Q7ZjM='
    b'?OA9fORUOuENoF;;Yqe%j}weVkRx%%@F^N8yY4zW(`VdwPnK@0gax59i@k3gm#hezAi=R)ebOW#y)wL)qvv>{<yEbkDUXJgg0XD7'
    b'rE$JXxTR>x33?H?Dk5}wX_GNR_i1rH>I10t8q`*syVkyCq+ILEMN1?%tS~D2T=wxE)C*>kgH(n)ZV^{`I2fRE(G&QMxG!u(i=H=n'
    b'^-=S<kE`|Zn6=k@d_L@R>QFan*shxF4u>_ld8$cs$~S$dj4BuE34Nd4z>!woi>J{gnzUQ(T#p$+y-Q*~?+|*-982r|#@I~?Naxx-'
    b'pqEMy_NqP-HFQnA_H*aJ6I&K-x3~4JR&{)czuDFqSH+C^m@HRu;}y=i3H9gQ1V>0Cm)S@2Ezh1uFNaN(IO^}P?5y8*r}%k<y>x>!'
    b'(_}dAoG;pW*V4k$)u{*~U>(Z#`#NIK<-#8FuRU-*W~RA^`tavO`Kj{P$9vIzhx0#cVECb(Y~l)garcAycuH)S37fZ`5j&_UEj|9c'
    b'MpX1*Gk<X-8Jwk@*|IbBHx?dOaMuF|$Gbn7GNbMUKPzJZ2Gs0&g|84fAqDarjr4<^e9tk{@GI}h$7nhTi1{Nb>eK0xI<!~SLGsQ{'
    b'!goe}`@?QhZ)3SG*yq^jWkyXWYfjklj$M~C>bY7jAYf-4B7;NKs1Q|Vh^_{vn@OEXU&x)F^qm)7^b*7?JZFc<@V2YzDz}j36+60j'
    b'7O&B96s{hd9movKRZg=9m${X<3JV_GzxVeZ)>)LrrKWY5OGCT9W_N2+gp<5&U~Jbs+<Y)7*zIOdPQDz#qc_b?d9`J0NcFOQVHQi*'
    b'U2ocxYFGAf8XL`p((hWCqPez(rWmcCYQ2nYM^0OKLi(ZpHZ!N8``TTWOE?F-X5@m|Q$<jH_8#I~3i?yNEq>1mrm)qR^wEO)ZXccI'
    b'&BcQoJzi$su-%pG+o;W{ea<62W%QUR_LOMJqNEo}ygtI-FM@t{=b?5G-R8E;t-!1w0c>Io_U%S<{F;Cf)u4T$_FaorzzW+kT1iAZ'
    b'Tk7^sL$dP<?pLA!(f1qH&CMVo>vUSVLk97;h5YN%s8RU7U^Vh&wtz2d;~UX18DgPW8F1E|q`ipf`q&un#LeP#q<W0K9R4{6W-Jlm'
    b'iG3_uizncfHyQSEn>-8oQdAwca@?{{W*6K@4nVn9P-&hiz%%`^pXHf3t<5Ko>JFie?KUs24cUE=V4=Nb7FH>)#;2{)EmCa~|8pMf'
    b'6hq*^7+$%IG4tIyPg69KSzCqnI%#cZm3e^cO@L`h9iX3uP#N)oE1vE5$@K%Fo0CjougkAh)Wog(D%qRUfiE_gdM4VDLbDf>{l{JG'
    b'exHBA+x_;ortnOKy!-2*D$byeyVCvbjq~e)>Cl_D(}yp!Q>T*YAD)d89299j9&hi8QoD{i%5-o{N)2I4?Fs|A?iYlx>Ecuw(%D|8'
    b')di(O@ZIlF--2|<^5b?EGp=ICeFPb8;~yH}0ejcER%I|Mc;`$%cOy2B{u~+Y&IjUBs+G2e*?GkEgD#NPY?>_B{)5!xXfxShJEBKA'
    b'IABZ$#$&eE#P5FCyE`c7W>(uMbXpkS=gQ0KsUBYQmsLFkvW>o$0oub6l^yUq4}cP6upY$tN@%X}+5J=+)cb}l^f9w{DZXmu^|T0<'
    b'i@3;@?%B=gW)}{~IiLS>fbG7nt6oc@BJa*D`mj~&0o1Ysi8rbq78c=jG<UJQ+?>*DJ=5Z=t2tJK%&ZYo$Gi1@S4L4**2Y&4>2XTN'
    b's!WiT&b3$El3nI|`jyc0SnJ!?e!g%sg<Sm^DdR@>LiUOF6&zxSw-#E%lA6J(Ny>#V-GP&~#?M+=>b$tx8GWa05V*ct4azDNToPl8'
    b';#rY)UJLP2ZylC-C%eBdx@YPJ%inh{<YLd@rq%)|9h?lHHgWjS-5n^m!Q2ts5l3^29o}!~woL{77_`DQ(z%GLdp%gLCW6Az-Y2<Z'
    b'es?s8X}OW#jypH;3X?ADsym9QrYWqN`@TnY^se{J`gLBYs8Sv4HR0|G14dl4ldzYF*w3#vcoVngKv>*IU<j|A9y>30XgOpAs~oEw'
    b'2;TybyKf}?-KsU3^`fdvjGm0zPBH7z?_N(Sf6rJ*?1L@t-LC9Sls3DYJqHIkJBVhJmH^L;5(*Q<<^C)p^nKdOrW`-F%(z6UgwBxi'
    b'3|w8Rt#CfY>ds^UF3)Idi43C2B<T*VfhSZRZwi`c;P1WwJ`WyFS0y>svC1MTK`WG~x?4lnO0{5+<>2hzrm;dcTUai!MmF~>frVRB'
    b'duM%vfUEGPH?|69r8^{&%_)!Xvp%j;bD^jn<lLq8&R%#Um;3h1Jr6T&03N=wlH?;mK=mk%y~Mq|QrQ$uKpBsHTCeXlDSw}CO7K?X'
    b'2EAJdT)G?bbkC#t0tj_hC7JL>c-TuCnxszkeQ%|Z3Hp>A3P0P_ckgZ0B!G9p(HVhqb5J2e#n7U#yt?g^t1azC-F{iDN5XHj7-OZ8'
    b'yS0`VC)2y3mwW9tKQ@<*s7=WHd{K{_?7V8{CXINXKQ_0~dN=bNv>On$@AI!(Pg#RqcX7wbQJIAv?NhjK<Ru)~3OHY3h`mxPNb_!)'
    b'FSYN{{g7Jt*(aNs9?_EyOhv$R=p7P{44+`LtQW%1^(_xezCXQjE8A+eb_ELh^Ny!_XWXeyWcI%Ii8&k|M)S$=p3nC?WZ{r&=H<=g'
    b'h~hnpSqu*P5G$U5xGxe-3ghZik1`yrXH#HNnGrO+yoksNyzTr-`#x0Mven3vN(aCEIhWWu)Xzg`9}Q>Fq>k39^R;yl#@VvI3m585'
    b'MF7S|t{eVx8=h5!<;bB0Og8yq;#V34qI>M6*&wU1J3E0BBXgP{Nk>3CtIhi;?toGkFtF!$Zw0-}zs$>Pa$KD~sBX+Ra!;h<aPulF'
    b'4p>DNjMQ8opZlsvxQVepmfz>1#9iQ`s!%8KJTC#&`wOPf5)$GJ#XGZ$IV<G6xL7E2t>8kO0O9$q9r!y;apILZjVio2DffxPo3^_T'
    b'Jf-iY(r%Oid+~{1cuK2c*{rI)9eWpTvQI+E_Q*l?$;$2KX|~iS;Y;mj6-Vl|8``qgB{0;}L;jF=4Cg!d1?Tlf3+0~)exUcka?^<^'
    b'sM0c(YI8U)(53tl($`{mKvdj%H<45DW~S(RmupqV^*(U%UoT~}mk?pVFD~7{6|y}x>2u3lylrff#yfX{>&5Sy_HL&l5$dcgscL2r'
    b'3;g?TpYQb{mFvXCxm?=PE219zNjLL0x1fYQeD3^C;k4Tx3uZ}z%Eh^UxI3mVK5`kW!28zpDmAOu>OPup`m>}6HM-yTSE}-}cv+Vd'
    b'paH$x#cG3XrVck{IcK-U9wkt0cd@ef!Y933);=CzrGApMXP7+l^{IC&4F#!e=rF!lr)Ya|<Byy;d^9v{H+Ztj4IXddsoeRlol}ZU'
    b't_P0UqjR}g<UA6Xz%x%uuV}R&`{e$9NaLNSChw}cj^9^$5Xg=TEc!&gE;gE1(jcp_VDAS^3?y6A?RSIrVVg8ol6Ho6>treAt=D&d'
    b'CGZ9U?q)N>HtcL0<;2We{budiLr5cE7PWECm69b>0$0-G7?-E5=~8*eM8X!Nu%)#Z#R26QZ2K_Tp^9>c?sA{(Sj2`VhpW!PX<$%i'
    b'y8F%%b#<^S*H(l-2dvhRIpuTP`A%p|AC`~a%iO%O$yVH~tR&~LU$Pjj*nH4C14pm8dmq53j-8J>^|qAL`i)*jX!f=0N`B7UkJ8o!'
    b'-ZLUQ$c(;Rv~?Y^9NPzo<!)VjIOiB?(f5bC#f_jsDeR`wZJl%FM)A~d6vzzK-i?H8w#inh_mt7!@#~@nRWHtVicRyJuPI%rD<HYq'
    b'4qZ$IkLxYW;wAd-4Q!SCE0KTn+eN?CY^#6{?5xXrvt1GFeo(DX)pZX6C;W24EKjj7Wz%A^b(IIb_06G5%Q?K-town!<1gcR*R9Oj'
    b'e!JHy;N@XFT^Sc%N7<<RJ<}=dtvYy7V)9Lcg)x&Ph>0+TrR5mSzxPaCF<qNCrb_}i)zf5U^hX&AYQ2sjRxRx7MR488Z~F(N3+3gP'
    b'?ac7Iwk_J(Dpsw%k@zAx(}@&+_nNKj3zMC^-IKe0hsVk_yMRaFdoGnS*maR&-fFaj$n9VPJ4336jpKWf-1f3h-qo47i}}Y{Rm;|='
    b'@v~&h7ksv<71mNXqB8_>Uwbr;W&`Ta*%6*pn7CdyoU>JZ*}H9vNi8$SiAD3UO)b6Y982Nc%N4Y`Qmr!6@>A&4>l$%bBUp@6SlpMD'
    b'tbN-v<wkR&mJi*@k$k>u+xKv?%wNI%s{@zV?=z0`J6G){GiI;u6c|_-n}C7BY#djkX$34yQFGClpm+bYvb#Z%oj<DldCYA>B~mS0'
    b'-8ADp*mS73XT|-Fd0ep41O@r%NF(G{SrPn(Kz#lCOsbk-{%M(q>$L_`sy7veI0<4cpW}L&TRu&%j~0Hd*62Y4TZsqkuDRH1&s69R'
    b'KH9%V^;nSOvWwGf#B~nZiVhHUciDANV(iLUHr%QTaD9Ajs7aS3#-O=fncJ;7q0ejQxgj*c1tjP4^o;-S|5Nxsvn4ZRro^}cH92NL'
    b'PS?zuAy@y^`7iLlSCTFXzGj((DfTVH;7!r{f4=1T9546*uX7hGFh$O@Qe2j}^jnVCbq;QDq9o|N%YSb5{`>#_*WU<AiKwEPsi<m;'
    b'GbCTNM33WLiL+hFliW}ee~7hA{lQgWju%Bq{Ck16<o*)$Td#{|ikhi#u5?ZB@i;^CywC66owx0@0Wq+3P2l~XJ-EA8`kl|aisb)&'
    b'ORi*VrkM&5RNhq5|9>_6k@838FD3qB5l-ec{qIHpx&5#AX&z@<sqMMI)SN*2)!yGrGA;9BS-QlVTqwETN6be*DN09>6D-qr(;xm`'
    b'#P9C?>WRvG>JJ&e?WhF2EB><XzZ)INu>Hqhy7$x0KMk+xqVSRA{kYq5z5h_AV5R;dYr3C~d}^YfUGq|@cP+I~;B#`2dZia=X?t?&'
    b'pch`a{TnS)Q$4syu*Ba+{`8vDQs=Sm=C2lhw)ppg?v{I#b?ct?#Naj4`#7-XYhmgZetOlXx1X-34l3DF`j6@VhtZ;>#`Dr3u|5Xk'
    b'JVBL=^!Jaf^fNK|eD-6seg;!u{u;xN^raMP(p~yUwl!T^N;a>#zb$Fly5#?ezSQv~&-;wRM`~cYlAg9HetjmjaH^QE3I7zY|E397'
    b'O0^fHj|}~{{y&^j5F|UbuMoIy`fWN~wr#ooUz}AlKMpMYTlt@#e_#BKc}tc#H85|#oZ0&fvH8P6(n~%bo%YPOJYO?-<yRA4p!>hf'
    b'9;E^IL-h|hrM@Jmnmy8g1NT>dcu(^F$6Y`CGVQ1NS#4?ipWcR_mLo|Be)RbwJ**FW-Zj~`ji0UjFKvGyBS=lmc{k1eJtQ~t<Bh2&'
    b'`9W$p-u!@r&3pe-6C-tG*GwJS{qgB9gZ?G<egmfTFWUco)9-NqD?oA=KK0&@-)gd!hTlKv^>Ir6f5`iFW8msvU^apuK$W_8I%sYx'
    b'?pGU^G`Z;ib2MVfwK&Vr{Es_IQEK780LsTuAFN8v^uhLYK&1}^d=yJ9BuM%feg8qGs->C5{CJP#Yd_M~k6V5k-wV<hOaVdEJYI37'
    b'G}KK0UyJ#DrI6;u)a!m_NilWTU-{9rxZiO6^O_$b(jQVid!J;=yPEV{SZW(xN?kb}Vg1u7%~mb*D~At!%SaQ0z*)YU+Wu!Ne<RNg'
    b'J{@!d?c+yk>g=DC#S6c@A?<pqTk5UCPjvqTi2pazQg8kMM0$5>A<g?42%j5&o80`M=nsFC{;rolqT~{!;Qx_gnV*C$$)68@>h&jF'
    b'KEi*+LF)9D{coiTyzPH3zDZIVGoGIYfy?P1^!<p^HRA`Mf2c)jx^(#e)_Om4g76u-z~=7!&tCr^K+;cZalHIVK{rj;|K4st@cCC9'
    b'c)zj!H{$)$$m8V{JklFJ1I78)O)|azK&qGy?k9IXQk>HG&#0spFn^$fWu_6L{}i0M!rutvjf<uPR^a^>>-~b^PpJLU`|JMyTEqu`'
    b'%^!M*X+HT#_^qK4`22S`B`+PL4+Q9%dHdT~5G-5z<GsIfyvnBl<o${W%}iU8erM;OsQ9;@_XjktUaHScdi*2f_+M`Ojf1J7r4Ous'
    b'0_QVq9{~Gp*PmZ8KY-DH{Boe5dhx~&^Z!uZPr>AqQ03Iz?jNh91o|iDdjG4ipN*#fh3PnpKght30F<K7=cz-c>_qyh(>3^U{ZD28'
    b'0y_Un>`x^5sK=-1nsT*2YW{Il%l#{_`HQ{&mBioH`rPyb)c>)&ehP+ZO4d?)Xhx7SjP$znui{#1ko{G7KkZ)nW&bBVSf?8OAV;6x'
    b'{6l>HyzEOOeyILQf80g4F24v;%2Ylu^P4OFN8<m{fIleD4})u_FDcS5mXyL?YQ8iR>c6U(f0hq7`oHMYKk>PG<ClN@%86;b=xO}@'
    b'g&1;G=#R)0AmGN|$d&jM#Vwgjhx6l2zYD7miTz}de<&)<AH4RLcm5!a|4y(e-G4KN-~8%Z3#C8kyznzce#iVj7yD1;PD&w!TPpQe'
    b'M)*CtKUf;~%k|Ss|3>mh=s(qgznIb`wS#N@U<rRg@1H~XqdR{i^+$TC*Z%<0C5@av^!cyD_9uUNsWbA1_jm4)Cc%2+kFR|d4Q$2b'
    b'KY8ZzNWV3C<5x(fSAP64{q6t9nEgoBKlJ`o9>0C$SEGN|>0j2bG=7%28n2ii$}Dj8)U!hA%hUgK{;w$fzexS?>3@#e%i{xRAL#is'
    b'q@=0#6TLq}>M!EcDEN_o{{x+W!_XhhcO}bB3Bj)khTk==Yu$e*f&b7I{t<U<{zpaeGbp}7f7A$n?c3kk<1@wa3%>t2z_&>GSV`wK'
    b';~z`3^wUpu^LKJn5d3g-@lOzaOQc^u{I9CN|G>1L44kI#zh>u;!+qQP|JZx?uQrk-QTTWN6*b=Pd?ocrqTVIpVa~-Ex4DCX3wV0>'
    b'(5$u|S)j3ySe0a(@%8_HBO)`avYwIv+r4|Xcc&XkRgsaI@y^JIOz?8g34A8*1e1*&rozf>qunxjNWvh<BqDPEIwJ3y^D;`L4K}cD'
    b'2wZ>emw<hXy8@sA(haDn1s{?E3zI3^Xe-Av3_&RC%B>#?hS0{<kT#ov%!@?u;}#Zg{`o)*T(Ncwd?QVQEdFr|GeA=;TnYc1?2n>F'
    b'#XZk8<Iu~<jsSUv#=mfBE8zmU!+e9I9F_Zk5EU5FkZ2A@+=YM5CA4ZU-LJywgeadZJ+$(O$%MiMff>*F)^id7JLMh~2y2C%k-A*D'
    b'``}?ZM_(410$6uBFUYabcXP&VgnAduCJBM(eES)l3gTE21Y>j+DjKGF{v=o=VnlPo$jilJ##@p!B}FzuEeA$&!6G9h+|3FXBqo)u'
    b'R5!VG2;udLt<H8#P#nj$py0Sb!@Z<O+E)d+H4`}`x|>bCG8wi)&WJl*g(7-LG>&FNN)#aXLLD_5kk;f(QtKH_{`F!K-!PS&+2rPS'
    b'$(KW{Pe{*X@w1e#g9sXP(q02OTYx#N!HP-1@DY&~8=eAnE@A07RdN2~{$OUCwG2_jwPN(;E|Ju!K=j~>1mqh}X7{V*+U3E06~k;s'
    b'qXq3MqMhpop~=$=#TjktCahl~DQgun&-6HkP(wDQZ3$9E_AG=Fd^`C9pmB^ysFZUS#L~k@d?X#sLo!i#j3r^Pvy7|&pq6`DGjN8{'
    b'Nh`Wr>&D2OH4YsuH}V%g-%ggma1=3;5f6+ffbX*q8kgjBL^0BJqrff_^U6RGppD_>AP&N*bcZRv0D@tjvN%&73%2AsqYXOgYhfPq'
    b'g~`rzaFfM0!H>BqD9Ntq{<jShp)3Tu8+9q;F&9|+Xu68UG1!XS0oBvxTeToMC%o2fIA2i_Z^=!;8wOSlsQ7<!cYxRc=bIob5sY2Z'
    b'GMxmtH3wFZ2u1!-^g4%jt_TZ9W;Le<O|ZbPFddXx;1vkkw;lPHIpSJcj7MHZMM*b7Mstx($u+ybeMm`IWg&XpDjb4kCs|UV0~}Qv'
    b'G~zuUe{wT|moaNqY)ST<1`qsTi62q4FGnV-$dQoxjjMmvpeS4KQsjYBzi(X?Zmmi~n5&8M!6py=VbqujTLE{0B2Va$Wg)oM^$9*r'
    b'ZaC#ei)jM?5+bcEisgX{XV}~W&JJsuMgV@1Pa~_&7bwhC6ZtN<&z3M@@S~!&xH;550g_93lumj%V(o}f_}+@>LV-+$fwFcO>C{l@'
    b'QCL2iHc6%5s_GMDEj-c-qy^l#)jT94>~y}xT#_jct&m;hP9SM0YebW4C)T3HLwHNG2MAtr={Q-;?_fd{isAUsu@;6JOHz#6RZUvU'
    b'wnuhRXRUc%&XQgf>Ij458Db>!grt<3sZP3<0SipHj?50%$gIdkdr^QdSOOTdDx=y_igLL|7u_)+{lba*EkMASq71U1!9t^Qe3OM-'
    b'iW{jgQYP7@Bp1Pqa2{hUKAJDMpF6*!5M4Dc!jDEkJu@DN++=)lAZ|G7aYmjLLQX%~yqw=E9Iy_49y#C)rh4go*C_r*i;AijmSH&&'
    b'S}a`xH!L@r1^Dg{<ARrzTjlu_xfm43%F|p=VB}f|#Z5*7#mQl19xmunP@<qcL2Ys_Q{z8mI!?LvSqJ-G{9cuQ7zWHpu`2g+d8be{'
    b'7avugCJEZc&E*#*vC)eYZd!_{w_x37E3ym=51u(3IU8X(swcjJ!4z9kFXlU4oPIbzI2>QR+qYa#+tc(ga7`n$+`x@PJ96E~w{73>'
    b'eb@2B*cth5Y?-5x;|G>&B-SXfV&=w<6`O%EvP?73U%Yq`vqS^gPlx`<34X|ligQG#yGzMgFJHcV!!W}{Ly@K}Z<$7tqNf$YKpN6B'
    b'&XBxuO>(;ChZ+LakOc++i(pRfaOX92k3C2I=AY9^NS_zMXP72_9H20`!@W#9{Dna{bYnuP^XBm4;QZ+9^62zr?7tpg9$s9I&-M@g'
    b'cKD{-<!}?Nvsht#ZGZ*=!UNL<7O?{(bO*QWOFRLqVA<(vf7;XP!0|OFVDg{&LK85_3!B6QtO>yD<I~q-E&0qQDbxNQOjqo1v6wG9'
    b'`T@6I3u~6EM=g(EYr+TSQ{zXbxKd&-C4V5n$fJZQD8rP{%XSlk2^x8r*&7<Ssx>sia9`0u00z)9Ih<-hrW(p-O-ST4+f0;ZuvbC4'
    b'8~`1s3`ZM?{n1y;q(9WfW}vuE;Zb}b1v$Q?FFJVa4P=z=T`pFPKbat(!INLViH{2{nx=pmjW$3;@)d<W2I-?sQp!L8)1?E?_6VVa'
    b'X^^IGSkm3qFdt|#Te0jl1Uf^y2B`2t31~fFe7>i35cFGcJCJPvIv;C4eV9ecx81ry39OI=Fh3l32KKJ@XH6gI@NXP|z9}P;y+jzz'
    b'wEAqwrV*9*;aytY-5N@KBeknaOOiM;kF8sPolF+M-h0~JWY)PN^l?{b^J|#RRV+TxV#hc(J(25obk?s+01>+@IodUV4t0I-k2%06'
    b'db#2w_BC^tfH7eRz>wWC-ANfRWwQ>!B`(ED0X|?#DqrHK`bBMJ-uGNr<jlK%<pkr>(1LY=8z;%bxXQr_>q?$zXLC8@2BF8l1^XUX'
    b'iBDdB>Q=;IqXyban$;`_M_c2O>c&M;b(64mFhJMIY`2~!Y?@rS?c;%pM&<$T3VIImA=B(>l)s||n$Y8#bl6ek3ZyV&Z}5WPoua}c'
    b'#osHbH^u$aM6{KQ$V@$|(wu-*#JC1ZUlY-Rc%WUvn|ymTaY#hKXa)!$LGp=6g*m0uYcl%r^$Ezw6!=R+FA2zP1!E)I1)4kuLZbh5'
    b'ved|E(_}8ufZ!dHLf|9g$|(wnmR-X`CXIqt@I?x*5_$q9Ii<yXz8uKC;QPucE<5W{H#OVHx-At{!IuY>1_z|RuR7tvjc9}f7Vri@'
    b'st9Fo=Rab~IcDMv;?>=K+JWD=Ei_y1Sv`%-Qq1KF(r7Z_8V!Z}?=wATv=Wa>Bcd<}F`#%rwJKg8zCArZB%|WuO2@R6bccuDFxJUq'
    b'2^o+9qN!iEvFjm{H<5ofJ+YUlXyp3q`7)3-x7TVow#*No+iGg?JpcE&G|R#L!-g|cIFFE*p4S8Xk|f|iiP_1FVVE6lFL8B8E`h`d'
    b'5I61Nn8lMNB{l@{gyInLZL#JYB%J_iT)BuDzdrqN@<xc$i>~&6)!z=z5BD!m&%uPfd{_SM{P1l5NdA-qAFS??ujEq~m;0AT2jk5i'
    b'Ui0$_fcpF4S|F$Am;0}e*FLB2bkn194X^Zs1(XsQ(qWK{lU{H0j!4Yrny>h35XYV3c9tTQdBQi68GjY?%)n|{pxuUllSgwYzkDMT'
    b'8ap6RKm+XQl3x3M*yoz7FCYQhUna}Jg5BUz#iElz9*DF}A^bp?!dPd3vhoNThuzF7rfhfM1~jcw%Bbtm6cw8VI2A0yKu9hEx|6+E'
    b'_tb#9ql3GT@nq5AAGmSe;|gFr|ESpNlGznZB+nGhX?2Lt3%un(20+eX5`<z9vZ)Gs4?N$EMBZit7X|M6F<WKP=0lPUR7Oi#@m(Q*'
    b'_cG;Lvt81+<<AZ<2>Nh`$*EwukzXTKGX8{=+9?{@iYu!;3p+8NeqtRSi{g7cpyMV!{CGL<2&8JC?RIx7qcoe$Xq(^(0H}Ax+5p}`'
    b'F6LIpu7*yL9KJY(c{-p8x8UAW_n}~ClF~+A09#X)OqZvp$9SiV{#*Fv;_&$J0RPI(2o(O5liT61?P&TMy6hG~k`j<C4)bBNPm={a'
    b'3m`iB<^K7vhnI(M#zGDY3;g`_^iuC>Fik$H;8s}s7n|8ywUg>;Rm8e4GTE*?ckto-96X~O`6e@ci*Y1Ox%#Csb_56Nl^JFM#C&?|'
    b'an8r9+0zVSy<J#^-WA>o1^G60Qx3nNqYb8b4dJ6$&yF;Q_N&Z)anQaOnWo(B7JdrZ{?esE|3wPml*jDa0(HWB;l3C*-H(<UMN2gj'
    b'T<C@@=Bt}qa3pSnMT|Vx%e))#dbB&~0t<0P^Y3YN4T<Z!8RcthNV+{_dvO+r5cB!t1&jrEX5O_#zqqMJ@n3C~q89>_=bNXe!r{ZH'
    b'j`YUl8BC9Ra@r?1H+9=xl`;!&;iZUIAMK#jz2D@U{EylC-`aXax$-~u;~&y~+<;ldlR3*ili^oq;B8}j{ZxZX(af0@QBj{29bHx9'
    b'(p;#R2_HTjy}?s5!?bM2_542mQTi8tKO7mRJPAuF-;$rr;&p`u3Q@qfr}5)QvAp6ZfPQtIbJ6@Wl5K|Sl`f!(TfRcysqqT2ha9%X'
    b'Ver>h@ElR<`w|(7p$AwEU<M+{Gz`yiGz_osT|)@stQ5c0aS$;85}T&;baVRcnxaz6>^<aqDdtqc(9>iRD=}t4T)#Qm|Mleb0{?uy'
    b'e<30_1K^Llv{MM0<5^y(Bssd=eCGU-6B^BCPZ_j0g=$#a?1Xx@1ZWjwtRExcdAtpN2=(6$nrrFQ@5QEzOMm1`R$vf$630PEdMf6h'
    b'bRvF1o-=`19hjW>`pVq3Y1gmx1^d*egETx@es{S42FOMZp$EG5i{=<xy#4QAk)*$=K*DW+Nd1o+d~o{y{m~^ZLlvs}+~xV<;a1S!'
    b'9bJF{adfbMJl=Gm@+-Ataz?@d@t{estRs%Vd8abVX8gf$?#ul3K2sM~-|(gTLgZ4sOy{TyF4C&PiSZCJSEcGR&Fl92?Dtug1+0l{'
    b'BbrE>(i;{^h@Z9z@dq(*sz@hk&+lc2?fb{ar@w*kdhl-l<k!Os6$D?A8nQwLuM1LSW*-TEKIMN~3t2ATX26w&ETP`5Y}D^FaU3b8'
    b'-ECN;Y1+p<)eAy@xdOjQ3WF<m_qtnyGg-Jr;V*>XUj1YnnIXe{{+V=ERcSm<Wk`il8&o3wQBsK6#U-f<Ycya*|6LdDxDD5i$Ykp!'
    b'RN3v1xpX2+C|kkn7E@9n-E7n}b0aQ54bdBd=n*nM(h^nDxskaqy?1VC3h**G@+G3+X-8b}?P=Wp&TJ|g<ExGjonSsHh@h*lIv(#|'
    b'KHLKbY5FCe+?-7VN(M$B2EY72E3`Hf%FT;zC({@f2w%;xFT(gRn=JVeP+qY^fa3TxfvJKbbPj@4g~2B`SWs$9N8f>;%<fg+q|NVi'
    b'^<Htu3EojwlLVpeh&2|FGC*BWB-dRD1{E6Ky2m%pFlrL(--vKzy1`8Rm0o|t|C0f#VwsnGFF4cf>GvF#*c6$pqnNoB_&LqV^`p!i'
    b'%4pfsDzkV|lL3>w%$5=q<JDIV=-c2cK>DVAMNr?ab?s&LF5xv`UzTX5WoaU~HZTu#U<a^5%GZ2$r06@wz%WcL1xA>~X?Gy)T|s}H'
    b'T(Z+3H3zrCwByxNI&`PGLc{ZAFvU61t$ZCba^SzPX?%I{msI(d*MX7W8t{!M36p<SARC>1xu>fiZ$&b&c#Bt6NvRruk_{|4Nz`1~'
    b')#RT?F?>Kb=^H1I2ot5Wx`Iv}EG>gfGoVSqK8YFQN^DzW4ISY`aSia}fCv5#{}X_8$}zY+>ILTX!ysnt9{=d%;aBNH;vacTwsC+f'
    b'bPsN>bV0#D0z}$3C7DZw9Z<&hv@6E}Muz|S*DY`nEQY=ATETHP!XFDL0PddKeNkN2M^v0EFYlDy1knR2FDWYb@9$9z5_Roh{0XaN'
    b'UEIQZn6rw7s^%%(MZC;TyAA@poOI3-82I)CBf}S~#V7E7($mkdS;q`$V*mC2;g|c#;^B00K;?_3+0Bh7k9;u;?$g`(@@&CFx$wxr'
    b'lz{_r&OXgQ!tdy5y(Z1O&m+y}>_2hPr;a|I&wvl52Y1eMsgL13n(}#GLE;k2-ki^;Sd4@8U;5Occ>u^UOj=b~Y1n4*B`x|B;s1)S'
    b'zF|oKYUE@x6$^Pz>HIJUWooqF`|<pKNt1r!xX1Dd7~~CGf(W}<MHn-~nc~9n;qLFJ5Bt$#o~Fl>gkh%ifiQZWI6UQ1;m^39f}$mP'
    b'NuqWQ`|=jHldl0uRHC*gj(sv;+y&FO0fl+bf*YV)e4eiY(hVkH{f5y+AYaVFIt3T&X+xgk4Q`@hqM!ZvZnC7T7<?n8Etoy*PpA9w'
    b'KLRXu_g>t$dg@e(LJMk0O#988r6=>{J{BZAo=3s-%>s<%Y=uu}L}PrfpNPW+0F3AY><v4l+j++%3@;Fmb8*e!E$%;JD~R!_W8$yM'
    b'6w)&xsz1!q00cHo`H)UvaPg5KX3Kq<jie5K0J5w&vUqHE^X~HUEFZE&!v}N`Ly+z}(8miP_xWccD?lch;<fJ6#pyKWr3u@|gq0B!'
    b'E)0^7zCXnn-h+_%nU3JQDIfohUqpH{N$&%3;pr(u!aB(66(9I*NTeS{=SahduqeTK;@|~MC`A(~2wo=yFabsQ7PBgWtx(vV=k>9k'
    b'GA>W*rs?4Va4V12fU6rmSMbbUua>7ENT$I(7b2h|mx~8H(0(EcC+zdz*u!V=AW1~yZcc*-r0`FZ`6>m-i-%`gWt3I&fSfNb$R@d~'
    b'=g6ot`4Z_W;^nt^9*)d@F7LZN0R!>F{!*|I!j(6dU`Nr<NcRCxCTJUfHx2W7MwN<3>?4+)J9>kp^>;Li53v?Yk-?rg>;<@3+17sk'
    b'm2Pb#p$U5jWQEYt(zsE_`*2i0+S}>;v%<6yxjS4c0_kAJ0B$9UAb@%?xtYN#ido_7+YfPYi!K{GM)&a&yhD%(Tqslp-DUuVbp+TV'
    b'_r&i4&|FeMl5ShvRZQGXA!Fu*)Ik>_KS5ayDliA2kHFZ>FVk%|$nhjx5Va!Ii(3#4vff=uTne3hu?p`d%k9TewCC#}`bZ23=J@Py'
    b'Sj+N)-~P*w1h<DTWc)E+aCi;I{eHwHEm?<rC?%A}T~WL^^cX)3BY1iRA1uTI%2OWcbJTQs59jV%yHChnFmUj!QLXog$EM^siU$Y4'
    b'8g$FK!{^dn<8z7`_ca9ujAnYuL9>V$V0gY$Z{NIU3k)kR@uuJ6GPpULL?78gAz67b2!+xy79`D6bl`E^=!Xw7XX$iy3cJE-4Cvu#'
    b'M&5kpws5GM4nLr(!#Ygqk*Hs=yGb+$BN%=o$09?FQ;)RK$S@{;OTPn_Kg83n!Flbt&x-kzJoTT6{S!U?pNaY=k%FIy-;*K@KN0We'
    b'h*bPc^q(5(_=&hbHd68vQGQaS<!9pkT#=feIEP0^dVVI(PmUBl7xKBoST=8H$8(f(gO3|Yob_HmEV<?M0ep+8^xEOKIT(F8o|}yF'
    b'B<wOP?_dRJ-Vur-0s?OOG0F<ERG$+i@Cg#?>JiApxO0Gj!b$af(R~3A4x|`~EPNUpyNEZ)O+x2})-RXWB8E{$RSb!g@k|IRvAZA^'
    b'Trcv5NChHME^uFiS;@})o>;x5Q_(CSf+3$&iTRK}`{R+q(>P$%Y#+swV%21T^Axnw3K+W-Bl!OK9f2g61XJZ1u};9Ad>`L~{Q^>w'
    b'>@J`%F3XQ(gcj!|Ds+E;WRbYUk348Ch>kAsV@OKGjJUy_TZumgyA$@A1Sl=g*<vzRS%5n*=L~#>nQEtgPlUKf#Z;+Lje(~7gtv@$'
    b'eSfSjfSxE)n6jl@D;^J?K8Of0i+?zuewc|H-v4Crf#{<pf)Ln%LcGU!@r>7q`k~lSK&ws}z)rqL2?9(={7EjxhZz?4K%oMN#y<wf'
    b'->{A<NV5o0I+@Re79f9@ka~?Znb?OE!yjLsfhWKJDOVZ4<`Fl;^t+vn{dh#5e4_TlQGU`n+>gihnNIJ1IO5x$`TcMNpXsFVhvWT('
    b'^TnTq>!VI3e>k#_I?H?-mf!INH23k>jq!NIHaIu^5om04+WKSgdDI#0k3jA5C%ZoayY0_|e*{*WoFYF8m2T<iIqQptmoNBz>JHtn'
    b'6g`lyd*Y%eujIKV`&hkPnjKW<_t_tFUR^+@<!re$ot}ml=sNN!xm!+Fe$H;z<t%18s~3ej0e21uw<`mI9|T<dlYsT}*4We#68{k8'
    b'^VQpT_z%{ZpDpQPP<@X1D|w%WKbddPm2q9&mhxR~!W}O(Nz``<+~9tGU#iMOx16%a^Xc&yU@*FX4}Y20E$_*d$ll7y4KGD+=&8}2'
    b'{L1@(+5!N-1+{gwwPj|7jcuLYmIwDOV{+mVTPAJ?7wJTx(Jk*~$~N2qA)V@Q0Xr+N3esB4lappcHO~S}tPIZ?K3#=~K?f(hhyMc6'
    b'iskbM<c$t^dlfMbwj`1aF+Mmwxjf%Lkkyfaw*XOiSrH@Wcr7gL<i!WNyUmw7IP%$5j*@VBQUm+4G}(aJiM#8$Jp;qbwa_n01`#~*'
    b'O5BE}QmydNpEdmyGad4Mt$7L2;cwMHl?xX|;^=E%gXagRg*tLlRe1dOkL+P@8r+3(fE2siq$Qr48i^90m*CFX4f~={9bU1bdaQgl'
    b'JEF!$UXr(TZ*pT2-GZL*zNcEIVk0e5kQ(_tI}k?z3L*0P3HSwWZ^j2yUj`oHch}%Q_^F^vg+U>)5PU;D3d)+1>i~IU73CpTSP-M<'
    b'HQ~gXbOqtaqB)JUk|Dc>KAxN2vMW`%bfPp)zKpN(-}#$L!C3mN6uU{NyjADEr~Lxj2+X5je);$r{{kt;Zvy5U0*iQ$OGjitO0j@P'
    b'9gxCEVjA}u=tnJT8yeXN>o^k^jP9R`CDVDCuXeS;p~Iv6k7w60H7t+D?rJvq&lQ_KXj~)YH(R&o^`bh;RZgi3F!sO*#(Z3%qbe63'
    b'Wr-h<N?3TG-@82g5@0#CUF}~F<Rwe(>+iE<HRB~~PiI)g<m<QEufFMPuT#nukoO2h37@*WalLz06Mzv2il7@qH^wS2%WOUi=W{GT'
    b'HO8hSS?hGs_lgHR>uh^aK0WOdZXa3r9bLQ*J1&X}b#!W~iI>W`Co9T#<UdiNg<e+Lq}!{#T`&IW@Eh9*XFBaK`Lqet0^Dbc!ejK6'
    b'e}^5+(~0Z=LrIG}_?_O}-ir_-7bc9dk*2)HGDF1-|66NXy=bUwu{Ci^6H90Xlre>tKR2sj5oi79YF#xEw&Cttl%)tMjvKeBw_U%A'
    b'UnK`ZGhK|c+o0CCHqG^tZXltE<|9SJUxk``Z1rGkeK@rH8y*+_!&k0QcQt)5*tuU!K1m;zBe<KP_ie4^F0kE`fBZN~;a!1qVJI2^'
    b'k~cq@#u3s9hlRc4Hm4YZTXFAmZ(ahYq7NuOGrsKSJwj*fb6?u8TeE4S{cm2k(jdotw_=0mRTP>jO?CF`9fZoa<~o>}qbyz(pNalU'
    b'@iTo5sBF=ju&d98`(@{sb&&ZMZU=U4rrWwf3*@rf>T9WvJ1WHL@c>~_A4ot^P&ctZ?^V3Q7U%7cD+8#e2ne?&?>s3w0rIBA)O{|&'
    b'e&Xp0YbGWl6{9QxB)8SXKe;>23sL08I1MVk?a-sZ@H@-9`yE~vW$@*0suUXmQ48piBf$n(w|1fw5fc9$V2Ru>9lhV@lhLvEhpBkJ'
    b'#quZReJYi4L`oP>;=BaPf*+ponlSo+3d0m%$+znWWA-O=Fz*E716)IDirkTqyXB5K3yoAN7odkS+_{qlK0Dnqk~O2Y4hic)(CY6a'
    b'HNIZ8B?oJAJw*SQ*P;L*9yVkBP)hF5+ipWOZs}}w*T?>e)ailt6;{O5OU_O^$JEl^*Ng&oLBM~jrNWZVq{hx)&^?nuEU>V~6Kv7<'
    b'c_y3p5ee2QO3o_vX9ZXysJO)y#^K}2PK;Idfh`>HN=@(rkPX&{DgGu34>c06sIig~w$!gnA^{RO9q^NFTyEGGtXx9IH;}+CSkpZq'
    b'-O`t^S$E1+y%N`5uR%i+0-e0VfJ$jnH0{mJUa!y-9tBRPY%0<0vl*RP=CpNksy`C;UGQac2jmLwlBfYoqx4gL-Z)>VlW3sk)&cwU'
    b'IKdPmx=%fk(8z5B0Rri02H3&0=bz6O^G_3W&)}60R74pKu)N+^f!>kr5_n1UQ%*&v`%l#17t<Yh5LYQsUM71HJ5x*DW1-i<4Pd_t'
    b'cjN%+4zI%7mxX-?55Rt}n&M^ZsT~yt){3>Ci0EX|Q+!43SJ#!L>+s`XiuG^72`CWvzqCp!&_m$;$FQ88h5qkC|E56uyIN=POZWeS'
    b'_2hVAbY<|qi=1&6MDw(7d98<bWx$=^KmWPAo5Pc}xc)H@(_LPk4Cx^oL@r*#AV>t<MP?~Tyt~N_kA29spUl(iY^<&3uW5al`k%X1'
    b'RPWh>oG>7Ffw7TeOlOjXs^E=ygOr!F7>jJX-F960TNt=N{j;lyW}j=`xX0K9a97@*7hVO^hZ2R?y!-3X<@oaO{5|$u8=sw@zCXL%'
    b'Gc=%dtsiMQzya8sFwCAt-Apx5aC0F0n-u;6Hd@~9ncD4gd7tj?>~JnYt7m6A3Fi->S{<t&-LH0F4`(+IlNoLrGSm91qHEC?9Zmap'
    b'li6yC6ymt+=Zuk<U9H5t{k-ab4Fu#(_+L1QVL`abGh-|!`T#xwcKkwrf=4wE;y!TYBnfzH-59iN<;#@8+Ja%iE9+6lN8A?}-3a-n'
    b'!_tgJHAUWh086{02Ra$kGw@LhZf+I~KUFNkvMkNeZ(ScDcS-MMYXtk%R~DtAW*Ffl3(=2LK>3cz{@(L=6)m&A%UDt@Yd2A6bkr2L'
    b'ZaFb%3_<b`b9M%z7M<=Dj}3a&iq!duTMnUF2OvqK`0v(={4xO&>4-|1{j9MtjJEETtHL`yu|Ze@9V_f{z1q`Osr*aO8SLHteIKjp'
    b'@z5hYGU0z+uNzn4mEUJ;9=>?DfBpto_ru90ESo=q$2+A$={pMX78k3Vl?3EzMvOdcN*l+5=Id($W}Uv3s`#A#Rx>&|!qZ$469$J7'
    b'ueVL2QhmEJF;?4bWd7<xU?~c&r=3cP`4)9V-6{lZa-Hj&S9I5g*~=$XSzm%GG|;=(h2xo)fVCdFagw;9WsD-`jNCAEJi~Y6C~{3F'
    b'unZQ)7IR$B3`ViZ0y_xe(6HeDlVNO+>}aHynWz;r<N8{*QO)0z9SKwhtbe(l>9E^)(Z?@unFzPwgQcVPsxh0jpyF;dzH`OP?V|M1'
    b'|AO`D5C4irKFqiD7%$OVd~Q=)<$qCbl_ny#+NWT_O{~4n@A031AHct`JgaQ$(!;Y1x`zUU&Tm5+1DBsFe8OV6QR&Nn&gXadg*h<5'
    b'A8Jww{J2XD0<uzIb@lJR&#r&z>Fdd~EQ+`3Wzt5bk-@ycwOuoe4a*7RC<FpDP1gc~Wy2`+hBlCFl9(>DeZ#Z-z;u{pjRJUP=v%&C'
    b'&HDgNhS#OR;ZhJ82T=rePMV`CnziJ|O_Ld(A+fRqLCC27=>(hCsVxP=(t8#Go$_|%$jhtcWIDia$H`)TM>=mjokwK%b`U_1oQtCG'
    b'bO$PS%Bpbq_Z$+!?BKt;uV_^2+k*$%Utlc$V2A&wTj~NqXTbcY8vdmDW&Ow++WrXRCF_DBS2BA*jh|%;FQGq%a_UCQpD2dwZgUA='
    b'5-ya8w}Bj4caEKpjD>lp!EDA)rugEH>11xN*tM&=9J%_b?KjjZE1q2bDljsOtq6m+#o%O`uQyRzp>IZ2y=|eO(0nN9ph63gV(X)V'
    b'MHrApctt&3+OXq|H)eIQ$4z2x+bt7dRlgc}K34I_N2-zRY+9zV)V;l~LDUr@A@VaTOIQuyS4lDx=(@zGLXRAi?W6loBiXH&?-j_|'
    b'Y2&(Ohby#To2*Qh8<O=~+-7A8i6MVu4}6g}I0M<lrmW;CVz(cme6q~vd6JCL_K=nPF$z4R6B2j?SrW#$M`!mgxM7=lU{#@4N^RjS'
    b'cWS+@`o25rSuFMN)2<MRU|`~|%#b2zxuKSsURmN%58k3+O=}tkhrbqBjqm_O>nIXH0rBx41)TBPTr`<E)|4$<f98g3xmWaIw`59%'
    b'<Z^;3>}rS4q$l>IyFMX4JMR(FsZ174tlW}gQO#Y?7`sY@Yg5`~GIbk_+8pba7n)M9+h3`nkJ_A&EzXAOiq>-+6oHYs)pQ@V)sY5A'
    b'^uv8^#r(D-Q?uka$@V4kunKcodP=LGQVR)c1elGXp0<>P-4{fi491iy{lnYK2l)4DA?)@bWtDpW0$Sr~uQFct&X+qZ=&1jNLL_*S'
    b'oc=Zc`>z<b)J5c;KZ67FygD?`_g>N|lG;ndpoScS%J;lc$4jl@HB0pIc&Y8csM%r(gsEA?Uv_fDl)uxz=EwYEJ7l+6Y=gy@vIFzX'
    b'GdEvVh-$uC;+^}Ht{e2Utb2#Cra&b1Yw2l@Q+sxw_X9y|{1YlC@IO|(bs>A0V@C%(0lvQzSU%f^cJ!aPiyQ8t+WMn@1GDX+)dWEk'
    b'<E3-l%U)B%mG0v<Pd@iA+68XN*?T?JQhu2=S)sW#0oMZd5WmpAP^+8ieEu;NsqWP25$5}^2bUKgC-(|CJe|c~0xh1TR0$%>me)St'
    b'&T$(GusMOSRQo4e%r#>3K`9%a1P+-1p?=68k2OOR;Z72%hL(tX+5@sL8oSfTekcvGhvxTqXBCXBG(2;)+c&Sbf{Mf>-^EuOw>UGE'
    b'LbWSRC@-K5wwsI!u9{ClfGL^ik{s+O0GGJZj==tPuM0Lu{&IeQAl+S)os_?{m;ZUSJ2I}Ho~Bg8bom%-*^JJ#`#|sET<t|zNb#tb'
    b'YIT_&Ekhs$^Fx4V7^O}NOI8}=NHWY$ls4vi9<(u*Oc`SjqB;+Qb2yoke-XeyKw^lL;Z}&h1t-F%l3iI*(SNO#;Z@oddF4`Ci}doB'
    b'qz^bwnM6ile=P{-x`t=#^y-ssyOJ8-Fj?Lx8t=GXxY(io7qL&Y!r|H#{0%QaHm%xDad|d@xABh1CSflH4U`AF-hJ%KmbR));OIJl'
    b'pD$C7M0{7tHI_-6)qBIWBq88*WJkJMTenv*fo0lkx8duSfIHDhW`-+9L_1YAAZ0WIkS)pNe@zQBoGhNhRS_C;F=bM}di#1D2Jv{3'
    b'wWTWx6Ff%_)~9gu=Zb0D!u!Zwj}pniGy>SI$Lve7%Okb+14sz)N@*#`&C#sCpGYo6hS(D?m40o_^%hgym3V*UImP0O!nofyP1BZG'
    b'(Cw7RWNBv}9!~43++dI(io3?#RM<H{QNRUNH5-|`(G<%ga3cBd`q|Tw8(0(<vT4VQ1T83cwa5w<jPF)-C22WEgLVP*EQp-1aphp>'
    b'@x+(W&<6C@L|}E>_2K-O?-)Yd-Pr;8fT58o<7u2bk~DUx?{yu*!bR$I*Iy9ZeC2D!SsVV1zvWrcbvgbuogyBWvHNJELic7ozr*+p'
    b'9xH-jsa$s9&c#@0!?8$xB4HU(36_?-=j0t-T`Ma|o`~{U?kNAQ{F55WslOjV%uH;Z<$_n^J=aC!Ui8T%`F$Z=E_jbuV#U7>Wg7`m'
    b'U<<z!(ggp^3f)y=(OeA|<9Rs|y;5o<WZi!SHuA<?R(PREb|N;OZs3hP+Q3_{iphSK(O45ZIiluudRiaUZ+~?Cj3{NR)`%A(QYPeE'
    b'$~431CtLFRctoe%br1#vCPfA}3r00oYiaj6^z(B`%KSGT*<9C|SLaJmY@I78``h(*mMSWp1k2@O5>oVp7>(9)@1^ll7g^cx!F-v8'
    b'M({)N7a?%yhx#)g#pb7+PGv|?22XSYN>+bOc<c$*KTP0J68<rK@)k34%Zws<fi4WBvac;q=OdPx&ByYJGk<2I>&&H&z$iR0+ehsO'
    b'3=+enFV%Lybbtom6&eD|FDq?;<qwt7vOCm`ErP*~y>7hCtaudP^8$0DM<Xww<<88Lj%J$tB>nXA-Ql^eoY27PfmRn~87FLmM#$(('
    b'P1$%d1MP*Ha6GxcozF7T30BMb9c2)cs~`xgLC(rX%_%i)&W%50(F=JSWB`8&JO`80i@xRc4beJX2)@Y~VxXBmB}B&)+4dPeP15~O'
    b'Ks;1kbeE{)+jZ-Ct+ojo%TH~1kPW^WD&M}XwOXUw`5dH2b~%Q`aQBJ>zb=zY>2&++w_b6Pzm>mu%Bs^<fsJPQc>AC-eR)n?%1T(F'
    b'?&pOJ$G7to&Dpyk5|I=vWiaNKI(Yuvr<zMRZ1!maJ9o!3%)a79g?ArbkM}8Nd4V%t!fbHH=O0c^4$sGjCx1UWKRtPWcyfuq@<i=E'
    b'9~>VO0L~B3PA`rwPtX4ipK7_GP<ZDpKD=N_x^s)Ck2`huP?Q%A{|;D;Pxjv*;(Pb2^j3xT;beUD27fRuyY&73<>le~Gn#;@e_NMQ'
    b'mOi9Bmuv}yMroWNHa=q&iQ1|o3r;{|WobLg-_^v7idv~zYP!rYP2@t8)K`|RS6sHN#6@+Xa3*+jcOlwy6(I2?!^G9f_j1YLN4+j_'
    b'BhxDJBr48#y>8i(JL(p=oJg_pR!%3g)fatZCAM~ROT`oU$r^AZ803?bpPwT$O1E-`_eLprUp-Ps`>Q9lhAfK2&)hm!Fca|sr4CG_'
    b'AJN_}CV<h)^bXY2%Pxvao}bXuTwyOX%ic~t;6Pk`Ln<&Z+)Mz~qY(b=cyr8n!mNf9e?|Wuq*L%2JDyQMb70tO5#?ipC-x|dAwv{v'
    b'3H9+ltTMb&dzMZoJh*@J8P>n#DS%wc=7;LIt-`z?r_1?$bwA1axPYIi6$Waa&fynKc*am#DHjzU&AyN&%}7Fv9NhF4LzJ>y4vGi<'
    b'J(bJZ&C2C`TPNu^7L)l;znz}{?d|dDZ&<!b!QorI-we2!v{`lPaLMlOG4YzNj?c09?Hf>L)TgS`)q<2Bpzo^^=O6Phr@lAYwX%+S'
    b'p|nSZz&aTe%&M)=h~h=WVz#K3^pNx*&-8djuarge86H7K!98X{?s3PXJ{^o8%TPy0mnVkxkh<Oalro+k&WS(N^#&ZLn4u(Zf0qW}'
    b'KJ8{WE_r3I0)!^akl9Lv-H>Y6mIGQ9t$KS!F%X^L+KyA~Jy}j1l{`~~K+0(j@`;bpQ@NscEFiKTPlk_fQLC0l`TDKpEkQ5vPKr@#'
    b'mL%}op1e=p_8#qF<vsegVe=Z~Utv%1q$3jfdIql(SCEe|I_kHYt*c02q7^#G&WZU-=Y>+RR+son@AJcPQHcv4_bo%Z=o<`kH381W'
    b'U^hw>{2L_-jZHNLvSEl;uWRNfpSj*(Fq%G#7$z~~hxK|ycZvj{G2eY0C6CFKA**QA?^eTln%Df&_7-^rCGmzgH}Ji3;=*QwTL91;'
    b'8c$y<5nrK5iioM!XjLKZ#vieOIH*j(Vlkd#2?124Q|v{I8h84TCxVnq2#Ca`J<dz-;a^xWQ+z$hHw&IH%5UM_={xZJsj#BT)fj6N'
    b'7LO>~r{tahxnV(+4J(~uutW?8WO^p5krzaW_?fibJwCA6t=rs+$+%8P>|$C<(E`+AmBH-P+tar-)#$5Pg6^6-DKw2igt?=rJ_fw>'
    b'<&_*9gUQ*l49<?u4qHp+VD*`1fIu^aI<_0_?H9CI<VqeNy+69davR<6wY6JiLsj-S2|lu>ZLC(GEL;#9XBV@$|6I8Z+>qJyl0Hh='
    b'v#DV3zU&D+*1=V5lvGL$k#bikUsL+AOX5lVtqfLIi6_EX?&^O0IpCgGh|xaAqab6RApUVOoo*>n?y2^Z*)B^It&PT{LhF~@>*M{L'
    b';|||i4DVi}1^pf9t`W!_U&aNvztKtb;NKg?t3-UP(Wxqv>$+k*S5d~!!YLNr5h7Ifb?ckSfiYGIK}!G}474ju_@8^demok@R7Szc'
    b'*MLnYH?v?mxH$Ut=;RWuG5HZod8nWNc65AvUE}*xIR=r!kX;>+7tDliOM`@0Zo<&cc!^CBE1u(%e5J*Fz7!Ra6-(ijhU3w#wmH?^'
    b'dBeihO_qCret`ZePr0Fo;i<Ff>gH&c?$jMliwaZOYlFLw@dRs1qbHW`6`gwZLa4w1hE$4F6`qu``zsv+@)VbpM`rPh*EHUlsJuBI'
    b'UmjjuzB|3R9FKQ4L0I$$c{j)IQ7Vk{(^G^|vozmIxj$5f=rdL_lQ$QUi10E}yt=zjJ2ZjrW_LL`rHr$s=->kN>JtLcLlPyB()sjL'
    b'B@vR6duh4&v1B>%q9>~rKJp@GJIZ|IZgnfK3j4^9g$r9i`7t|e8R@ScwYE>ky<xc<m^_xOI1Z+hAQgTBW#`UOY)v_zBlsV|+XAgr'
    b'<u0<x_53%%p2c<RWN+?NvUDW7bZg&)sqy>I+3TxG6Fb8fZ5#TPAB(s1x8ThN9DzSe6hZr<t_OaG<)Hr#(uce0WcCqD-peUS@<r<*'
    b'+uj-}wlN#iNOj3i<nlFfFiXKtVsUA05m^>1>-$PRs7?ibcs{mhM8Cum!Cg4HS<P3eWR6snZ@@e&v7~irDBpz<I&!<WqUBuOv=JgU'
    b'OjrlLtS3+&<5?n?#^7y`<Mw$D@;AekicioLsC;|7-Jd7{t66#^D&*V&eHGKeYKHWOX0wp>!b!+$WLJ552g5a=K@l;Y;+FAo!<fZ_'
    b'mVb=JDY5}x{hg6Uh`|FxE|9uHX3uiAK(58KR$R06$MQrtnZY-u)eDI#OPSYn;-O^ROU4%WsuAD@fRWDIN>Ot0$p`DTj@3XFLIlFV'
    b'iV);x#N+dr>c%gp7hwcCKZ+N{l5c}CbugeLk;x3GfXPCzJPERT<Okl*{fcsP2qMK?&{t@54J!fd>|m#KIMW_Ur$T3}9IEEnbT<n~'
    b'sloV;bpG<gmaD=6)wR;lp;-NI!sK<OTV9osx<JsO`y@&De;2%pytw1g=a;|p_HZKE6l=#%<36uT%9Ej#TI}UJ3QQ#2vshMC?GXdj'
    b'#M@=X5^MuSD^z-;E+EY3g_-;`ExMX1E4P}vHZ|a(`|N$nn?qdR9qzwDwII%Y^oXxlJ9JvC4WPHygGAl)?_Y7FzHN;F?NSke>->id'
    b'Shj}L%;^2^OR%!BwVUWWUsrRzGE`~**AJRkf|bJ;iofz(qwQlBC~Wg-<{9xYRiz&1!TI4nY(Q283ATN|^?^0$6$$?7_%-6SAwD_3'
    b'ZA%h3R{bs+*Xt+{<wM<gS*E<C2kpJK8QqmoY^`ncT}85xQIEf1+b*RW`ypX%p7BTa(A@6hNv4X31l62og+V-^!a#*M07b9$uP^zI'
    b'zTAEJcK_)3WiS7HwtsQ)^4sIJepZmE!)w5mt}cq(b>aw&QtdFHhqsb`l#8#F3s<~ak^QRICZ-XV!hTg=Z$5pQb@UVPvd=%9=!G|m'
    b'1x4Fyi{nnTy`9%hp|zA9k6Uwc#k!Z*`3ZS4XgtU&(xq2wPs-?Yg;GFe-VA<$O%m?zms!G$67$Xa|3sqyPk!MO(f#EYi9FA1pe|Xv'
    b'm^q`~@8L_S^Mr?82|urCoEKN7a{GD-_d>6&jMNK-pp~9m#Ro3W4-d=WZYNl5l%iX;kQ=H^uYpn=ybPlbj|d0~iy+n_AvI_=!@|?W'
    b'!Q``bgJgRNk1MC~{6;5LXyR%6;?#SWZVMGp!s)vb*gUmlSNr;LSNq6QLb(Y{_W{XnWuMp-HhsbSA&b+vH2yfwJF3w~UbE_31$miC'
    b'Oxe%H<mK9ga*>Qf1iMA9bY)<X8vvu;$hATYsx&Q^4}10$?sJrv5R0d%Pjo5wHOtD_)r>V~+X6EY58d6Wev&%y^|#gz-<741jwH`W'
    b'&)I*oWRpS$gN!2KQ7GQ`5P8F^39ckRt>70FvVGrK&G5L2#XF}b$Nxt8-G4tE@1GyM+ryp~n8zb)S2x3$q;sn8+$Tvjr5k1alyk*S'
    b'5Z}%t%1^H32g4Mz$zNX~;@2diBlWTh-fgDO)Yo-NiTZY-b6U(LCw!L$V-&f{%5rsGTb13qL~MMvBQHct=oq5Qt0`r5#lY$m*N;9<'
    b'X0a}8Or=Bil~l(nAPg4e6*y}QHH97oc+NN1GJ#qjm8zK)*EiottkD$ACJE1u;wvtMqtrH6s-C>2<nYBk7EM8cAh$d3QIgZhi&iNH'
    b'80B99;@4}W8nxIFm;{UHmimZfTboo=rs$U1%jQwe0pL*<ShumD5|Z@e0>x2a#&gFDQL(L3l$?x=o@!R`>u19Hs43-zX}i)Y>{I}>'
    b'SlZk+!#aTil*knau{g)VJ-j488JPcA(evE$tiP=GeZz)S8aR)fzsjRl@(Hn`y8Nj&$etTV#dF|-hiP7Ci_9&5vdN3DHs<thw1YB>'
    b'tzxTPmzxBahAkC_enh#n|9&;_C>krsp^%EG`fXSXMp^i(_A5%?>ORyB(1t>vr%Mf%UzVkqbW`Q5cKqs;K|78G3@UnOyXIf=t@~iH'
    b'6xTzz`j@_6FT2@Ewo>VaY`4oVlZxYidF#7+k+yu@x$f4F;=5-P?i92Z5>6kf4bdgaByYZ3$JU&g>8f8t27Gx-N(xer(Y!5H#;u}}'
    b'Z=D!$kX0t8kEQe3`g;{T*3+nF>#tJej~ATL>zZ3_`J=)Uy>7a@QG8OmsHJnswLz?PiSjjZtJ-}0(m6l@7SAPLPG;$V?lI}jaV!zb'
    b';9J$Jgg=@h@ulF#KKTGr$f0`%Ks@Yi)G0&kHpe{hAEkhv!U`4MZ+UMMxun)i?7mpf9$QJQ{F!dksy~`ZwvN6Pb{Dg9n|5@&1^lnK'
    b'YGvuF7h4R;*l1q=xgmgAsTnD2C~s4&Bd-*NHj5~;(JaYj@%A4?3N<^ax<W<It6np_`U6pVss9%h7EmO3?$qRF>3pH~Wo&NCEgaoU'
    b'ca*}Hxi5y=rxY`-3u~66r)B?t3p-r;xOg_iFmY7>US%jA?W@V?Kdv@a9xHm4nd6(^-^WLZDBGK*XNBK6K)rPHOo`&rEiqmMgi|}e'
    b'`%5u^zSuP3NAuQsJPIIx;#@30k&+U(MYi3z#;WoP&|Ph-YgL$F-%@B^tc?OxjeV>p9Jm@-B6>Opng!QM#I)wM1^46-YBU3j<YgnN'
    b'F^xj>^|}R`8hg#X&Fsr-wJIQ$muQ_l4}xZJiZ`taLBi_WoKkAHgRh&2i8i*imw;4CYuyO727lYUB&{|8tB+`1HAIZoj;4@*X@l4L'
    b'qBUg{x58Ki;0VQk*5p&v6kP<Y_wZleSHg)?xC4GTa=<&lT!O%-qCym8T3aPY+`JLzE3y|9=_s7QIGoNy(W#Q9c%LupEZ<PzRq=;2'
    b'sJzpPvJ)_|`GO)ZSGs8!p5tgZ5N~@bn?c|=+!+;V46?lkFExi^7stFVG!)~9<vf8f?e1>X(Wb!-(tkHZI7dJwlnj0chu*1id58p+'
    b'%JlpUziyqYooss9L1vu|2;&KQ8b`da5mh*#R>xOZ+=WVHq<yLR`~TE?>S1ah8<zf3m#cDJ-?2%J-qN(%tK^Fv5L=9q3)3woj7@s7'
    b'i4L2s?ih%C#%l>y!~3<3RfsU?{7F`<AWh5D2U}CdifvbT!(xGFU4lw;zZL4OGO4~)6k0hR`HQllim>G;*Xw}LZ1V;x6Ds4GeJHj8'
    b'QW>WwTBzWrn{|VzZCRS23htynh=$?2uC5h3$YeXfk56>dGT<M*cF6UOdwSXyqEirB#bepTlrIt~mhr5}A-Q^70O2|6j%*mf4~(v>'
    b'2Lft<pW3I=fxu+8WH(H7Tm`oQwun-n_#?H#w3Js_I;bw6ux?-imQyvlb%s2Rh?L;DgLOKNp53E=e^)J68*~-AzNZyVK+%4Arj;m#'
    b'E3a#;Ht?K+4EeP$bk{5=y|qXG{vpe`zWLOvJl-HHj!X4LyH1OMS8HBus$VnM<Ac+a%k%w%ON^m%XSAVduehno>sm@q&l?D+eZn4f'
    b'WqY$OQU8J|hak0OQa$+f8v8QA?5G><KmG$G;&_Y>!FWtkaXiLqUgNR;AOC^k1l9u}WCeT0woF*60sCvbA66f8GC(1LYzU^<y&CN@'
    b'kSq(Zkz);8lnRVBV1sNO5$*?=W)UHjMY8EBui%u*^;JkAH#SOfw;lqeG!sn6EOE;~JDKBR0BAZ=q$!At#PQ(8i{ryz_YeNfamViu'
    b'FW;TM8S^nN@RECdW$B&wY=JAje1oF+GPpULfDN|bzu`>YNF90#D{_nlCf;SqNAP%hu?!wQ$d2i!vs2h7Ui=u0;G-Gs@9F0mX5qm8'
    b'>m2T;2na!sl@}g~{RO+5MDyu<2EXC5J!H6@GrR_VCfaKsq7pa`LQtaL2T?pw#>{|=Ti}s%7ElZEc}iKwIl2b{*q4A>0%+ZyAPruu'
    b'7N39yQ(D7gbjSB!@6%=Yhtq|qGR<A~CbZX%{Jh9t%!2#$cD_8r6muR;IGD0vk)E?pbFl6&FcI%H@$vqQB6R1XtlrO`0MH4GFXaW2'
    b'bKbG?7~Z3WKj$_X9_L)*mGkrY6g@qXZs{KYd+yUXhRJIsq^C0=cm8EN2mUY=f5lhdup|H{=43Jz6oHSk1+iqdz(o7|@%(;COaJpx'
    b'KbB7bo^RMPm`pEtyD?mEqyUaFikSUqF;COuNy1R690=$8=g$B;YSUsPVF(!`xmAi8*RU^dfwcKfP<3Qt-k*>D$$W7aOy35SjB^%%'
    b'vZ3esULYG{Amukaf&hVn`u`NKKK*R0Ptn^TxkBu?AA|lRU4w6=L`$=W{poZ+{zrhl-QSCQj(>m!Cz(;GjV%`c&77qt^X2{&rgl6B'
    b'GvLhv{N9XIPG`ijobG@AG%gs1I$4Y)b2!CPHplEHh#oF*D(B+*;alVdoUq{SKLFbJtFn-(v{XLK(g18yTKGe1WRFyY%rRT;ua>u9'
    b'nJpil8UMVSSJ?)lt<SN}O+#)=aZY^wu;d2T2e4tMpq;>=oB#*h&A~iWQQc&mry-cxg9j_X^p3FPNCMrmV{ZS$YtM|;*<y}qg}C6N'
    b'L_OH`*o)^OM{PesCvVDP5N#yK@aZs!K8iQ~h9%!%+dtAO=5l<wc&Nu#42neZTsUTJP4Fop2hLXEbduhZf<yvc;06b?ic$Jq5##6T'
    b'LaCi256@Dm+kihVZs(uVpMn=&eFN6bHdH(**6z(DC0G3vbk+)39i{E!?#H5d1j1nwOqFNEY5~LY4Sf%04oFY3(16;wm_J(nHUVj~'
    b'TH@3wF#Ln?MM4ul9#9`gL4Z`V^CGxo`w_)_xQ(8hls^o?6ZV-TD=pL6Vlr1bf_pya3_Ofk(XRcjIB{=`siH(-52*(C33ZHz{4m7C'
    b'B~n-rwv;Od7|d7c^Z~hJ8a%N0XK?O^S-`dFKUsVbOs6P`MLYvj&Bc3sJ4rXsmOmOn3JTV#3fR*3C{}<iiDSt(`7py!7)lzzHU42}'
    b'{&tJ`&iBBCfYr%-CUgWj&4kx$hHYv-q!>#1@;qEBtsG$w&2HXZUY_MBm3$vAMTDeyx0=NZ&?NKEw6L(V$#imayF6W-PUAM-XdZJz'
    b'WWoFtR#^c%#Xy*1g4%<kgXuxeHS%#Gl%-<%X}AJp&}Pd8S$#yP=pZQZD%q-s&@aLHSy&gsZ_<IMco44+08`k1z5f=E;lXD^MRYE1'
    b'ZTu{RVTmWR6)h-^!n+yKs&fwGs|)J<^=gR$+-Yzx%v}-;{OtDU;10UxZ|vdod=Zlv5W+qa{{VUM@Usa5Eo|wpa5?}nFDaLsnN>CV'
    b'cCx^Vd^fDcHvj&piy!uvLZTr;qJ0xM4b<B_-N!a&LSo?WreXeMbY<X4&?;7WI(mbA_jgphhj;hOhoZduS@@!%nUU}3U)hZD7>NiP'
    b'gR&6uK^Y-_7DPqitO}ZMr}NLMCrJh{4;%nrVfF-)D=IH^h9);N*l@9q_<A{9ux^wm;C66}B}v#Z-jG3k4=RCcg{p4-&X|ZeG^`Iw'
    b'!T4PO4w($UH92D69i=Hlox-j03x0sYl#QbVNWkeRrN{;KBK=|59Z$jq2@gbvd_;LFSyJu7xxHA0ca!B0L{JIfy#`}AJLKc;4yDPw'
    b'$xCYdK*WRvgu$Ei^&Hf6#LWphDBw6g7Mt#i7b1tuGFlIPn`PVumd61L`yc!OUX>%5LGgYvn@~0*TQJ@SGo#Eiwn*o*U`qbR;v-v<'
    b'@FsX`Oro~2w-nLM=r`EQWbWsY7o?7hNz9_sF~?6rS}~kUY^7Lqbl4%zTM^RF$NNAQ?LDQ|OxSeu3r^rY&)j=U`BvQY#E>&gXszk_'
    b'BhVIB=X($uc!!cKQ4w&zxDCK;dUJVtx==#1=^3Mz>QYnu{3(!8l-Zo(tQ~|i9t-f<afZB{-!Lj${qr#vnKG|~l)?J`oySy2t(~AF'
    b'J`KLG`1Ql(d<sU@OzzRae7d@u{Q+3?En^gHIZFS|79k*hSE6}-6g=Zn{^#TSKA2+XK3GyrVgSk@8sS7CjQ;~lvBy0*1HWJrOp%oS'
    b'K$yz~7BoN$oCo9fXH@_8^91Zlb`wltj(-H)Q6WkT>39z0j^0<gzu@t*#r*D6l*YsJv3w`kBKm`nO{US`2g}9e%MrK@3lxA{>5H)Y'
    b'g{U0*v(e4N2{N9C-Z}bV_{MLP)IfPg=)V5}@U41?9B=e|=_Vyi2%XHMH-8WfuejuD*h!qhaIt~skwh`43!bt0N3jJ3ep1il0WNBB'
    b'c?`Fh-;)U8X3FV;KA@=l17I%Ljk{fEm|aYLy(qvBRtjC`;tcxpk>vzS6pi;$q{6vaPNq{q8Qi)mnkIh$#4#&Tjr6|W$LzF-Nc@-u'
    b'pIBy$gJ1#g{Evco7L_cWeP`NTn1U3Gl+iWxL7$F#7ZbDTu6_TnT8Ec_>xmR?arrO%h_^a=8owSRf66b*bfph#y5plahbNaumq+Bk'
    b'e$}zoY$ZqrE-CvvaD%{P7nbn7zEKG~QG07-##ZDzhHH)D*c$nU>kXqIN}|{sI>yK|hmpsu*o?g>4h+MOgD6Vk(2k>_={d2#)nK;E'
    b'Ms8rb%p7|5$T68ev<!#YFnGv9Ct;EAvLuPO0&4h%=h~)Y_~s}y<Jk7YVU)Px&@>|>@S=nzqsa3Bu4yNM;l-oCABLW1JAo6~!(_X`'
    b'h7ru1jchCSVSOCi8`;c=Sz?aN&|rq|#-ouDL`2RyUDc`V8IjZDHcYqU;m~tK+jJAtH?72g{ff=d_PxYN{KN{)ATUfebWGT(aO5VA'
    b'J&Y{Fh*-ibHZr#uDvT2ZZiUQoESFh+%tn#n4sCbnIIc5dUKqwEv$g;kj4aQDJr71h!-So2d<S5R0xPr(+f8CG3B$k(6E}!PVF;9H'
    b'B||sDS%hI|+QBvpHMH%-fKB!j8&<;z?4cV6EVPX<vQ5+WV_djs$T#Yo@yo#J4rP-~{)rK?!IuadS<i0L?Y2qx*eDpf4l|v|8U-=X'
    b'!!UFh?3@n_;ChZ30}CXPYe&J*G?LI6#gXlKvF#e85um#9K)^z-WyImoAH@d106ujC&kGq)gKNjY5knX|+L%f8VdA=0>;`rM+%fbb'
    b'a}?OV5jmzA7(>q+#el5i7{J1b4NGbJASP_r9l5}~$!O$mJP`9);>SZXHbU33K?IG4e#D|Eunc74(D4J8+2)9EkCe?k7<7OaPr1w='
    b'F9mafC<UgX&Ik-!We6#aEemn)_P1g3#(${3#vcfdKC%MX8FT1^Ad7%Ylf(}b--|sfU=9NgFhMo}r4L7m7rP*u%n^{LW7-A~MjScM'
    b'vMPGSMv0YpBg^y|kV;^I6pDt)$n=1HLFk6oDDv5m75DNHdiJ??@_E+(d7$Vatk!50`*!FXjvK>HqMT)Z7#R$<Dm0BSi7eZWyl@o3'
    b'wt+xTV&MB21mg%e{~6XpXZDbR=y8WYK7j>W7BSNvC7?dBZan<p`6Hkz!Hsm?idXR4k@xUa_Twd)AD+T{k6YWvy`_70?2Le3EpzCE'
    b'Nt{?Ve00EO00sg%6i2QP=7Vn!{b3ZDiOYtt97gDY)E&hZv-QV}X?i0g2EhlWS7LdN6C}(7oi`j>?r0dB77JY00N9lk=N*v0&$2(2'
    b'uAlI#ZVf?S8WtLa7Kkvz^8FwI(P4m<2}=~jVD?0z0SeR)0@x(W3t{6tlX-?0jjTt@G9A>AAArPkM@C`<4(tj1ZGiC;S;KH>MNw=s'
    b'u&DfX#J}KfM|mIKKMFBDFks*y@kh4dk0LjY-BIX{Y%?B$sBjW6A-tgr7FZbg3DAsbT3``^X=8<U<VKeJxKWcBj7rx8vjj{_5JmxP'
    b'h#v*MV>4zZz8_l#2n92G9CX+9Y>R=;w`|vg#dTfBAA-H-8lddm7;Nb<u_70|3Oj*KAF;@`Llz~#mR{_$N6yLi%`j%(kXZ?M9OlR$'
    b'dSPrio^OyZV+KB`$v7Bp#A?sF$wC1z8|+lrN;8QW`Xp8imMd)gFvh(#z&r#?-p5~o65(H=n|L7@b|c$Eeg1@@9k3LA3+#DVa1d^='
    b')|O#Krr{@GI5?JVI5AlNQS^i%fK5T34Sn#z91qCYVjlP+XoCY8Gk0XU5g7JE&oJx&TncaxjS-mpLpuO^Fg)`KLz@OHm_35cPb?O@'
    b';AqAM$Zs|@hA<}=jAz(<7KLjz{+=ImjnjwO@|G<p(HOTrxM9yo1V!BdP9{t2$aW&|Vo@xOz$S1l@RogWmLk}jVGw{v9va~6*$kK{'
    b'8IGdBHX{%ZZv0GW__pP^u5Sm18?g}V#u02IIw+tCht?<=c@g~AV$U?(Fos=cVC)!90Iq;F^uUgEKux+{kk}wDY-boIb}|G@Hb_8{'
    b'7zxm57#cqK623ipCN!+XwF29A{o%+P!c=_*R#q5?Bgc1#VSp?OUT{#*28-3qw1;CxcaX5qMvR#~DOPqPhlQ8?do+pYt~oM5$yv$B'
    b'HDDPm8|*-E%!gq9h2Q~%9z{58%LmC2JK$lP;C&8pHIv8z*Z)z2Mou&Yh_L*T9fqhDy(BSx$F$-wasvjw2S{<(dK7R5@+(G>XE>fc'
    b'L@(1oo7M)UXBg4Q7{wze@j&|}v1tOk8fIu&hHavXu)wu_)Sv+fPhcH;WG1jU4oEj}OTgN*d}D}+c!>!*iEXmA+q1kLgy23~AdP%b'
    b'Lk3FjFm^*9xXTO^HX0%(Bj&ia6$}BF*!4gR+g=b^4*1%}aPyH^VuJBxpzjbxc9IN1q?-Q70ZX14E{w<A2uvxq1@5+OxI?f<B6LQW'
    b'2b>p~eqz8@jKG6uFdYz8b__-f*tFn*2H-#>V4pZ(rg_%p`a`!d=;R<Vhrrv`2x9}LXGftQjR5Pw88Y7m9knhlaL?1^X~(Ev?21a@'
    b'+|9vI4q_^zlt%}iNpSNS#AXaWgFW&C-%C7im^k3dMULgz;Kc>-J?<<U89>h=kaY|`1o-8_&;=^6VXDuGOMu2Ri{sc#M$8XvFqA=G'
    b'nBYgcFt}s*;m`z2+JDyhC&n-anPG&WHR2%{C<YK*z-%zEVak?eIv_z}kX%s$l0Htr;_<<@2V21OE#G`jT!7-iRr5zN7@DyBf#IXA'
    b'hxFrlpf5qIc%~WpE~h38u*-XmuU9ECI=@%?s9-G^p3F%?4@2rM@MGYEXC0YAY%t^&D~Q19OCk`WpyN!(9r@7^Y<&=fY?#<1XLCKS'
    b'yS4{jsWpltgAvIYAXgGFa!njCf)8kNTbsvEbra;q$PUoWfb9f5Vj2;~V3`$woe_d)4qa#DvB36S*9Ng-#U}X5p$7{Jvof~8-GOBR'
    b'xont;2Xiou7`3d!OdH6@_rb~lt{6GPbsT>uc5cke*o<Smkt#}qJ|m;+Y?Rohg~1XKrC<d`%m>85RyHi4Y7;089HkKWnGJ0pL^wPj'
    b'yS_QH9biMSDV_lZ*aE|KW8boXl)(-I&1i*D0#X<ZvV?(+4JySlqvx0{sHg}mc0cw!0|+{HMlpuyVL+IC1fzhv=`#yFG_cG@js^3E'
    b'XTgc|0YU#6B#Rz<AQvNd7{DSY0kG5v$P&Cc)3y@}?7}FB0$5&K?|ysn;?2?iuP3J$mq!N<uOx`6pZeftvb<e|JF?7hx+7Yi@%98P'
    b'9z5JlWx-saC-Lo=Kb2QxlC_(2<6vBR7AdV)<4n{%)-6@d^jt~SjkPjgzI-V!ziYvCs?Dd^rScO)Z-i<j;YB@6v%xAwREjB@W11>_'
    b'5QCVmhW7{;0|3Qq#{Dmh9!(-%;ykM&m)-`QMew=M(1zDttgns*kE#{0+Cbwm=ccgDPN-*P@UUY#mUYB;^U7QBLx?pnu`K5nSbVvg'
    b'=5_H!S^PbWUsciSDE(Eaq*cm0ph$eO>hRPerO<Vy*yrf!Em(^1*0*CpWQx5_^uLJ7Vxtx;pon$C#8;wlqOSC7L2OGMTGn=V(eus8'
    b'%MvD&FH5q)=JQI4!GF=-umz)n-4WCHNt`yPB%6m+!(N2i=UcGmw7cLVl@$ZR7VrjIo->Kx&lI3&`=uH$eg_|JR?}e7N2^eyD*vyv'
    b'*_@u);q<bDJ=Yho0Lf}b+^$Vhsv(Ev#Il9~vZWEom9`d1_b{KympxtbeLs>+-d9?<@G5aJU67uw?(>F8gNT3AebL%iX@L8mKZ6+v'
    b'SjqOQQpb{4sO2?Im4djU_AzgjrgZZl5QEh{CKGn*QW3iKkFFn)t7V4Oy0PJMsum(Fg5px(;&LCP`1t(rZ2w49h27|dTm$fykFSqU'
    b'Utbi9H!j$eq%dMgkjmY>YkH%~cbc9Y;HC1J>{Z1-q<dJDu*d7+jprZfW4954+JQoJ*Hs1<EkyXwN+${_I|0p{+p=PUu-Fq=9bPfM'
    b'mv_yov?u=;?VR=TS!6J55=LA`B|^1$9<8WD%^iNv3j%`9NpS&VhVe1{F|Q_=vkL%}Mc+xI6pAQj$S7qLpQVB$j9RX-SWqxEr54Kz'
    b'Q|_N2@>9o-E4ssl6N(C^<NN6<9V_cFwv4=(>hxjkxn*%zTdTOCTw%ATIc~T8)uvl7@UCUlzWX)+K@Vsx8;8~Ye+_?b1f7GG1z~ZY'
    b'so7i;Oi&Yz;Mynn^^Pl@o;IdZ&0<7sf$b@aBP4x>M`s~BQeipYg%o-qcv@R;HX5v1t?#Ul=U8NosIsgw1CCZNL%VIVR0f(8>D!}!'
    b'J$zH$(G8$nRhpc(&KK6^%5i#{3IFrkCUPY(`}O?v!`a2v$7{4Rvd)a1rb4*gjRz3>cGrq-eLK}|i=S~-Pd*!9(t&sGyYg+S_bZ4D'
    b'EGO~f4AcXB-^_%~h|zX8abOE}Efr%MD(H%Wv;`v!%hWb@DPci$JDw+FPy*QGQmpeBO!G0=$m5uS1uHt1OyK{Qscf1_3{jSN%Hw38'
    b'6x*zF;5}*h!D4PNL5kv@TU{^`2VJzT%S}f*{AoFUwxcT2)!OaquUAC~YIh)d3XC4HfQnuhqp6L-dIIrv6`DD)z2ds<34pt8ZOb_Q'
    b'wBbI04`P6Bp>(>~oxLYz@U(E8v=JIsNZLIu?DX_hniifbtXVZpS<e=*1;MX(yP8>$MNQ=Vt(G5W?6V*w(FrKc?7Q(IFYlDM7OLk)'
    b';Y!p<gf(or8S|;l5<2=qEjy*@gjZiE;$GIypfAj+x}JUO>w{Nb;nmsmHUerZ)oMcta8>ress#>QC^}y4XqoGI6c~zGfzGpFme#Hf'
    b'>MGRt!7O*syefY&KpXRmWX<bLxS{t=mo)VHu9xVT<>+qqQe|w^hn?>FXY+;PuV8zvX>b?DfwtIH7j9jvi2|MMHqT6&bZv5}v7$tM'
    b'CyK3RiAPGG$o<`<$wWzTZ{A^|7AJb8>gi=w<LexmOpX*ZcsdphXU5`^g3NuG++m)>r!2(s2vPF9dZXCvnZwS0lwKM<fX@{aN3CcZ'
    b'Z!Xm^(vlk#i_D@x9eHJ5w@5&xT}<AErDjWOyS&s>et;57&Nl0i($O(;MWIr{7DIqaEN-hvynw~YJ03T}Z0zT<0pb9xqyIjuBHaZG'
    b'@%Nb;Ml1uO?N#F?82Wt<%~4hZnFc8a%!C>c0WXZ8a$BX)vn&sL1kWxV&e;tpgIq)aaiQ4?Zr6XV*z`e@hNu1{*|B!n<yMx(3`!WW'
    b'VnVZzBf1?40%ja9<``|phF`NWzxu>m(GVJC5wpc6KCh^0+WI~1YFh&NlO&MqZCV4p*k;4({JYYoP<IW-ftPtzopCr{-j3x7Q6YxK'
    b'`)E*)&Lv3EyR^J3k7-z68{3hG2tCbl@}0bygO>erH|_Dicn@UBQp(Xyx6(5t`=x!@vI|X6*ry3yDDBh^-_x@5BBNWv_mN6Ph<PNb'
    b'yUMu=Kb`rL)H&CsfF{ZOn7>+lk{{#T<u+agbP-mjm0EytMDc8@9hNvr%6Cjzz)Vq<x9m#Hux2;qPtCon@q`NLu=Ap-!(a>hx%$nC'
    b'hkw;AY;TQz?CAU_1x8L86}l5ZYvCZLwPUgsIGh(QM*&p%Ff()FH=LvZn9s1dm(7TP+U`@CwSLjr%TSZVx&<yxFq_vu8>D#yw!-vj'
    b'@N-K~fu4O?13v$)1ixErTJ|))MV!r04<Q@u{%{|pU5+X^7NlqCG){K!C41S#pg!1@mebSdoT9FEW?@D-fW7?B?WglJm7t8At6k9m'
    b't$GBsWjDC;dzChP6mo3r>g&0c)57xj<@2s-j7MEr8^O$WTixF*uz3pDfAA|<?4p%5wl7>^DU6#<rmA*<hQ(3l_w;shh&pbaqEv-W'
    b'Zi*_S!W-~1pwzmwrU-%FU1P?`QSr>JY!_snAoh+<mwm@YUl4u*!>zxZFN0~{Q@^6-*SyoE_(twFep|K+;dNFqj%%CC)1$SdBYvq6'
    b'j^h@*(j0$o6)1E?nwYP;09I~>TzNFdgvOF9So2&3FUx6siW}%(WuR#ncVFif8Q_C{h8q{_-*PiXj(c6(jGXrEG5gYjz2h|YJ+Fb='
    b'1h%kvn;YT$te@9P!34IQ?C>aOQ0x*q<7KA6m0a*D$&?T93pjSaWDo9^pz@$Jf}%u$ly_313<fOGiI#3a3$A7U1vV~5zyKGSfADPW'
    b'tk;V7f@mR{ZE9}a8i=2y(w~a)But!_WpJM$3m@rIGzOof{fvLs8$w$I-)jYoA_S_D_c}4q9DXmc^y8xL?NPMi5Ur8iVr*J2WLsF8'
    b'3mghdUx>%IiIZ&`wExj&UV(YC7{mtbBLmB(OD%}wNpLfpr+BH(8Q%t<MA}Rt7Qxq&rEAk@1d{KLE`Upp4)%|E0@%Un`}aqeK=qCr'
    b'`qnV=V`ms8{>U2z(a>|4>y2#NvSP<&{>UCVf!^JEjLY*w?3L~~Mik?9sn`h|!}dnZi$c%$EXE?wHazA8!N@Y>wh@-#2xK{JJngNg'
    b'RnnSk0UV`AGgvJ&SL>Rp_cVgNS!AT}W~p;}&Ef5`={+TjsF+8%CNZfNoXAS5u10M-(pUZc?@J6U-;-RS^o`1^-zsm)w89iVie%gZ'
    b'7?>0Mq6p-|yatmcyDKE<wQi6?Nc+dfr@tM(86UjcKl$}=yWMIAgIhP+Z0lNqY>;=P7$LV=_p@<`O)Iep^>jMN^v_6ifxPZ%YPwU)'
    b';BDBi?mAxzwmWV)&)E5bTeQ*oxLb{|zx@bKSq#ErWTG(QjY)Y#9ZQ0dWW1RysUR5d%&y48>BBh0@|o46xX-0<Y&L*g@wU{iV)iag'
    b'3;>oksmP7p4YE0k8J`GJN%qWoZA-Xf#mXt2-EGbr?|Cs!k^lnyf+003r<$|-)iUiU4XBI99pZTfLLL+-u4yxjdPWm~Vdh`Ak|t=@'
    b'NO^=N$b0=;DTu=Jt#N^i8az8N&GNI?nArHx9{y{SOd^^TSWGY<4n23adRW;&DS)SZfpop)#UNcRm`6#5S;;*7bi0~;Ow~16r(R(>'
    b'J{FP}zYEqIPN2KV*=!woT;ZD6<Wlf+){GM<rwbqLX&rHLP8-~iQN96J2e{=#Q-x_=Zwe&415|)Qi*a3R)0eDjV1a$T<z!Q;TfET2'
    b'?<N#?^}73rcbm|wHx%(jPL`PedcDmtxdIGt3>08(I=qlHoI)}|E3UYVOP4WlgdSa=+7NtB359Xwc5b`a70PIXDz~BDu@FArIE$yl'
    b'6z7YWp?{8gRX8hSl$0WiuI==B(_FdsY>yshfC(%pE1Gw~=u43)vYqn!(RBiZKSZ3;hn3CW<6lWp2#)k3=znAnYI+@hEXngNlOu$A'
    b'k@@w_#>M7dIKmv<&+khK9z}0EU&RIh0hL!Sr9R^?pe(y>kn=5RfV^PDEv@Jkwz3`$MdD<th$ssBVJ2BnT+FOXNvlnX6QRuJk<{43'
    b'zAl7k`6sd=#C^Z_>qpJ0u4Uk&D!}0lUHe7zoDIPf1+RtA**}Bs7%k9qUT6V3p<?bl(1POj#d;wfvuQnA-!FXmsANCvjgr?f0t(FX'
    b'hBGn9Ff^@tAdi%QWM?*5u^U{k!`EL_O&IlhTx~XA+Z{RtL6?JPdUs=^_vy!mn|cUqQ12>N^Y*or7syXmQ!Sy~xjZLRyI;&du~eho'
    b'RxYUCiM}k_=OE2on!%Q7F>5A+-m_V8Zeu(kq(ms?<Z!|8UN`)J;HJUkZhQ~;Fr3wVk>a;x;XHx-HglzR%Zf_+Rex$QDkEOvpM75<'
    b'E@#d2#p(;z%-s;F`o*WB1N1!E^9>RCM$KPIh9pK>lMi2-U%erWBs|0IS6I3B!6rW90J_aV_M*<J@kZ1<P617b2(nb$2Ee7uFHbZi'
    b'3hp*~en^`1XnAROTb)JuPF*5u6ShUIsSsMr@kGhSSBD98eZw&tRDOAo;#SbYH;mDGq9R-<en8AY<C$>gjl%~ZG`zG$@u_du8=SLb'
    b'n&Sth^KVM|q(O>u8Bm)f6AZy-aWLr(iiFTC7gQ0=Wr6&t_!>W{tPNSU1uQGFx)=ud6IrnvO6<Crh!Pd+Y08!R{Oh(D2_9tcZR}aU'
    b'*vz2@pg=yg!5#&z>nrnm6Ntnrn}W1TAdy{U=uogu`Ti7XEiR-{Zz*D$CY@z`;_E`L>etHcfl#Ll6s_Se4zwOZ4J+{!it2%N-MKD*'
    b'wyFh+-#<waG)N4U#GY~@+eCJJ20cxpl~>;hV6e%IQO4FHuG(8XLF`I54a0LBEw8?VW|E~Ihn20J?QOAYSo>P3VZj!Y<UuLBDp41;'
    b'EW`wADp_E!YRW3PnJhKRu>_NNiRD}}V6O_LE4ZlTa}{8<KuJZy<}R?x@C1j8UQ<>kW}xj)r<yQiG*as#XNEtAvO|`uQA%UXSIc|K'
    b'kjCOgyjqYLy2~%d7~FRk=*ZGMmE%ej+ILv{3ACDi!*AVB)BbY7DDKq%r{2@rPp$iXc;uJ5Bc5yJ26v)~J7OI%U{BnICvzMC1dAKk'
    b'j9-5F_!<AIyS|``rwmAW9&5x}Va%#Z6y(bncjICrVrH1DJBittVb%NPp7^$lIZD81bNIVlRRmk!E2l)9Vx=0(=(W`atjtghHHhet'
    b'5R-H&x2&=(P8`1>5UMb`(C(DFlo<g?>=Y5jVG=MJ(Qo4|pT<F$0xdtn6_eB|Ew!?+S$CQ(7=U|~MZ>638WiQgb9;qNM-5>R^PF3n'
    b'@1L6lrc)A_k1;8AxiS5K_wnshK_PJWo?vG-E+<T^j!f%KYvsn}6BI^m^qfZq^Qbl^3<lIGSJTsnJHYiLRoWABuJvkVzG3_{Taej{'
    b'2DfX&1Tq0tW{%}|;p!gTJgBXL7P0MhpqsoN<)#qTZ`#wow)&3hqVHCBR7PBjTiSkhsqWlv_0Fmo19uSq@?CemJ(zF*8hDlg|7-$}'
    b'Xs8*OCW+8+5TYhXt_|$BE8Obqw!OW={pEN1v+d<+{MmlhzWzO3(8q~~$6aMyC(mnTs&1+jSUO1&M<~}VH{Z)SH!|CXlp*Q+u}F6w'
    b'gQ0=7Ke-El_Tke`2se+9<I@Rt-|UghLb=$fWDkgw71-uZDHTHSX!j2t3q<#a=7<yzv#bUSX~A2|$2B8SS5Iyu_92w^=-;rizt{6f'
    b'iygTpj|sLXn^!aZP40S2Z$nI7>rjB=|567@ebcL2rP%)Zx)EjWp$hAm>ObZc4g=ttu_(03xe4rWdg{OSq0(xG>ZY^tA(FJ)r1?-Q'
    b'j0+ojdcg(dbDuAzlW@u}7#HG%fchA#Ep*gxW%&h|t{{cJ*c!bSXnXwy6|&IR<K?^~-ragB>Ba&L)tB1;Cmz++5`<iq+8?(F)8@x#'
    b'<Jk&)GbI*Fx{BT1FCX|}Sxs&zn*rlQEdDQYj#jJe${Bctg9TD~g_OL~slfVVx{e5E_L|QDYVzcGjka&s|D##|J8RY?2p8m;#hSu+'
    b'&!tmE#rKO_%7#A>D)Keva|eqFywFtnJrC~`vc<E3aq&^vik4L4aJA&Q9ay72#g^WA9B9%M*{KwwA5^P$KQX4ZPpc17kk-4S9|%K6'
    b'NoU|ih5;euI_=lVQWKNXyX%6Ak132vJ5zg;IFB3yr_d5+-!!g5Jb^Wsr@$tkCJU@4{8j(;=<?l%*GQ-+WCCuUf2&gI)@zwzvlXm{'
    b'AY}=5&J!K|U3QrxJ3Y`c(}tp>^6RFX`fGTub%16yE<8xwnGTN!H;7vaRNyhj$SNkH%p%S>RmETAIbtNdkO2=<V=ta@Q%qo?P^t*j'
    b'@c?R+vn8(wF1hnL*bmT&CyU(H)dg<Y>LSmP05U||uS}FclH)f==X=<}fCK9CFON>%9RBP0?a}ce{Z@ue;R>|?3qYg<P9*a2>FfUu'
    b'tB8Q%Kd0ya1|&rd6<!q|+dsZMJU`jLJS@Ke#)W((kNvJfSZrM50c?9GJK>m!`ojHw81SmY{r^M~&L?!;!(sQ}e?5M3QL4V4O^#Nq'
    b'E37h7@;V2xn{}NKASvpgCX*qBz;7LK_5m^{DEE+1!u85rc&LG&Qe=}NDA%aT;M+X}mQA6XB_#~7CApe0i{tAkD)S?sKADL6v)+k$'
    b'o)i1Mh7<eEkJ8%?@MWp~#^d{{(K4Ulz_f;#k<{nXl2-9EU&|D>9*?tWbMYvB{S^lQTA#9BsVa%%^6Q3u&RaAjh!Orr1YS3rfJHCj'
    b'qdc;igBO!jwGr~EoDq>UCkr*3@Djuj9)<=~3wt_=K*h!r&?G5FX^~7*wxlR$kMwY$QNEtG#C939<IHixK>=cID}V=i><LUXnPTSR'
    b'7sjvq10TdIUMe5~ABP4TY_3!}Q%_m2;7r|XQ+Rc!p0J8yt=5?oYF6Zi$9tvYtLMvgK?9=Ji>k-~Ik^{4p!H|uv=$C&zWMXq%uz@v'
    b'Z03)RlQy;^&>ELydzvlgovg8{#9<-tK7uFMnH{v=s9Jx7ow+j9T<M%7^lM(~v8{cTwD)a$WNTcmbK4pPk}5*xiAZR^7Y(ms=>{kb'
    b'tPm)!&+*a8;RW6J#vXp6uHz+GUN^VPH!MM80nfFc(9ADCEQ%v5jAH6a?ZrdO^5PKNm3ndFN6hzz!zc(N-?A)c1f=RYfoVFiGxROf'
    b'^6W5vM4wvSFvF40yd-eLC<)`hW6bfrXvnbLcVzmW?M0#G$9Wq=u>^;-A7D;$v-E5NUc^)8ubZI}IGzzjo(njHfj0`7<=P`-<QR!L'
    b'9EKr~9CmlK9QZx<{n&8rIEh1R7zS>zZSy<bOGdDKQDA#k97K*0he>1x*uio*a{S1&?Z9y&JN!N^TN5Bs&%x$*$#4`$w(T2^&xV$3'
    b'!E_xz35+1I62~(g%ZcJq5SYxfhfZWfHazbnn~xN_KrBIMB}vRiKuG{BwgWpzV3UW;F@~_5Rv3mqvg>f@Tk$9~4a<pxAP!y2hsBN='
    b'Ow}-bH+HPZa9q<1O>92xMXntg*yP)YV?Xfy(0kON020?Z90jAu_S}(cjx6LX$FqDZ2!W3h$8v|^AGiN&G8$o9>ez8&%MPO;h+@OS'
    b'7P&yLi5Et|6^RkMqmg6#W-v?)7rT>VDUu;j0gIj!mykIujAJ$oM>cMpm4xQdwj&devE9)y83IPY!YWxs(^WW*Rv>EcKrzR%quKMU'
    b'nm#l_F9}EP$TL|27_h+eg21qtVGPZY4NDLwR>1tBX9PC0lOXmz<^p8_uUXdUG5sWU*I=$0#*yy_BipwP$HOMmL))}t8!TDFAAu?1'
    b'd%-%I!l>X4F2!OV+~GMF=%a;b{`E|R1nZMHQ3$dgWNVyw4EwJ-0So*Xgivf5Nj!4>*z-rA1ORo%Fau{4Tj9`%+{8?RCnFI0j)9$u'
    b'hp`j*1`6JA=&{fWu#64%dX0>cJ7kGUGD@FIX*i@<WtmF%Fd6lD@*?R$1nguxW|UY%!w$S5s(=w=9`+gy!%=K_A#7`G!}gki>&2tQ'
    b'L{ZA(I0->xJ$hi*hE+*Gg;^0SvSSSse;5ajZD3br77m9t3>_q1)1n|t-3MT8K8&%p+Ks5YAFg6Bt)GK<bkGi#9~i*Zut8vHm|z-U'
    b'cWy8m9MAT>1XM8yozMl1X<AW`U>958NtgwsWI0diN~=3V2HI%|qS|(i$Om;D`o3piV`UTcM$EuEh(=D+>Qpt?n6hohWZ=uy*%zT9'
    b'5g=;k)EjUog6TK~`x}p~GrnciEcM}e<-Tr4aR8!hI0VaN7{#7#`5|x!YyfC7pp+;8r3jKXvPK}={1}_hht9}wjToC=C(nb0?Ykjk'
    b'W^9Cpo!F>zK<R+lWduXuUIv!hXy~{@f31{jkpDkId6ED!8MB$mg2=NX55$f!8hW;20^<R(g3R_zH}ZpFFtk|2KwZQ!*n(cb3^0^H'
    b'wLLRBu^X7SXM(X0rXX0lV9t*M*Byc|wjJ0#Fz_AEjY8@^EMtOg%}zxyaHC*vDF=f}qh)S6IcMV;rq@yvONu~aHOqL;GnjZL6L7&j'
    b'Hu_+j)=w)IO+!bGMMKb%Uf>4~SP>o@IczipnL0GVeDG}sMq#o+(KI#Z9HbF!ni&R3$XozvMlRR`46LQdcMZ$)LkCRDcCbn`g_Z&n'
    b'$R|Ait1^=<z)(D(1O&0JuQA30G{uZa<s`ksfA48y`2Q|C;WU2cw93=;<}zei5i=Dq&z9Y+TlI_PyvOJ0V!c^`vTdtw<yFa^T8eB<'
    b'-LWl-ja_}IRQ)QwjbXc*VqtAP!LIO;N9e@*?u94w<<X2tX497E4a=}$eZsmXy`pekr%34C?_J2Qt@>QAl=oba7rR?jhV0dV5!u6='
    b'7k?}PDHG`KrgibYtrxj#(k9xP>4C!q+Ksu!&@voz<e{(!Kc87<5F5_WbKS%R<Iami53F(Up`u~nIKjvR>kriTNUu-j>paE)Y$}QK'
    b'2ur&;-p_f5i|yKacU!zz-?e)Ed#_JFoG4v!%l%u#?Od4yavwZQ=RwTx@h;Qxa$YE$3ikJ-OM0}Fz)LCOD-Y$Kp#YvZ9I01~@+4$U'
    b';XAdpxr$%Y`AW4c-YbzE+FT*+ISc1Ku?*ct72}Ev+Egp9f?CxweQL?KD#T}~|Mq@;{kPWnluL}&tyblh_106|XcTMXs%{(JHScMq'
    b'fge|VZqrJ3ZE{UA{PT7*t|o1jN*x5VN%H^N`}XHHjwH?B^;dLwA`Zj|pzsDk9WGY3Xj?IQoha{)gXSU{K!d^x1h{C>lE$n5{VFr7'
    b's_Wg=04UGx-Ne`if$pq#R#sN#_mR&I@n=54jr2rbw@&VvhTML8+&5Mr1X)$XeGB5gXmD^k5F89y0SJeom(?-go?5_f9`#xd|5h39'
    b'?RfBR@o;Y12%Sg3w^hY$^Wn6WqL|SDo=4-BX~Z4(m@Ow?Ezlf9hzgVPc$`@HI;bY(dmyh!j)Sc6+N4I=>aZ1vVLxT##g9KQG3zpS'
    b'y+Ca{8T7(W_geZWQM|H8mAitMeUZvxP`1F8yj&BG*kg)1J}?_W(R*&l7a1#08b>|DG}N<5!#-0ShW#klz76XwL(RoA^u@OtJEcN;'
    b'g!yp?(h*%zl$?MIZkJ^o1M-lOcER@vBOgNsbBaYRpu%Mqzeu|}AlvFtQ`!s(dKyQ_D`Yr{MJoaLX)#KaH^e)*7CEXSuZ|in0#vX{'
    b'Q3D%yG?Fc@l33<wTrj_^n(m3O_y!nA#DEr=Wca5{A>;99HD*8H^KR1ErzAv455tG|?T+ImhV46!qP4}}0mfWs8WgGa5LWp4!_pkP'
    b'SG<*cq=v#3n}D{t<G1?m4$bjw@Oy0(-umv5r=(4&_{~IffC@L;9{Y(~^X!w?t505!EfIzO8D0iX?9bw8N;tCx>gQsCIg7Yi6-ib_'
    b'%7mIs@ohIS-S6X#X)TXzcV#^)368(RctZuR>=Z}$q>oEy6iJPGQl!TtQB7oNo}`YKSogqL?xCR`P)p%BI1BtX3dpU5zP-w+mg=~-'
    b'swvI?B|h5%MvyHJrY)M>f1#o{N6cH*6Qd#!8YqSVFv7S}R3{Hrv9tu&>Uco3LiaS5A><zYus@FBu}J1BLmE=nJmJFeL^~N3!E;~f'
    b'grt$#5(YKIOHc;kp$<SQ8A%s1R#BCG0nf?`R+Zu_MBk3in!~Ep#44F95!)(qKAk9hF4I<E)EOD9?)P1;cmCj2`<lDees97BrN{lQ'
    b'x}A8JoQs$jk^Blr1k9}qGWM0Db74Q9>u7jVc5UIH2QZs--o-{;VXN@cvF3^%0dfES2Mpg=A7Zn^<w@fXdnB9xiJDRS4l<hsZX-k|'
    b'XY*P)8X3Q67M(eZXdeyPe7Rtq0cD9FsM&Ty&*LG{WIdQ-7VwoY0H--qj5|mgVK&p%dDC}=VtF`SBl+9<)o(jUXkh<bW)yekaJaf;'
    b'77kZcXyLxxFYJP?&sTfBSl$W6x_9+$X*7Ui<*Oi(d-*`CWV0WXz8+()KqT6KE!fy+86+;UK0Y`(+-IC?p4Fg|Dl-;NG{0;BhqYXg'
    b';e53!SgBT~Fuj6Bt<0lRHQxHCl9WDReA}~8?9{qRd`!OQFqOOm`br|1B8L=@zkp5yK-EkEQ#B9(_B1Q#u!V*NT<tUxBu2H;$|cw;'
    b'+2L3p0kuk#o&?n`JA&2+5i*{;jlHM^O-g2hqdHcQj6p6c@RrwY!PS$#UbWK{w8wNi*mD$=DDN-2XyQuA-FT<tL-Yp61qIJW&lIc1'
    b'D~e%S3KVJ>sce1EED{LW6mrhv(N48H<5JL58I|qp+~UB!C*Y}&fcLe_ijb!AWqx-{#m5NY$fM$Py}Wh-%i1ucQ~+5XC-7aJnLd83'
    b'R9!xQ*#r9dhX!EEK}sbes6-;=XruCnVua2$*ia4(Y9TuNl_AZ+G5x2J(5cJS-YVxWvHrz{n||pF));jB9%hcU7$dIBOWRED{rj~D'
    b'{B2@RFw?Gkxcc>_9sx26-(ZhidtqS+F+rlkOqc6<j?s7G?oQn_<bF}X%lXuXdm&BPd`Q$6qlo`b;4l9Sz%7S|SQ7At0R4a^33(sM'
    b'2IvovdVtSAoZ9(m@_d=ztT#E_FG!pv+S+qPChJl}>LBbbZXhkQoWMZPZNh%z#74}%W<MotTT2Pa0~7moIFA^Fnj&KYoM}j%zzNHo'
    b'aDx@0EXw&;5H=zzIPU;h3LUZUFUbWUGXOm2+%Ygk$0zHIbvShXG)rz-x!Wb1DF0yJ?KTPCEh;j10PZ4TT@);rrwImyH2D_Kgfdmg'
    b'cfwo+WT8NVQ^(LiuNS!w+z<Wy#j~GYzqy2uXp(*Z^3C@ikjSHT9p7PW7!MR9+%KDtwfg>;GL>;*Vr*BjqhSeXX4We&6B;sq5{ffA'
    b'gI-cB2CzVw(NHn!`OtNDv>70-OG8L5{~SZkYbuU#M&=VAo_$QMNBW@9Wtl}^SLt3<UTgYLMm^(a4jbY47sK{626$%=)TbD?5!hQ#'
    b'T%i-yhmsm0Mp8oHycHRlZ_(fV{dPIO$%06p51AjDEpI;T=<b7GhD@<S69J@?)1?Qo5b|8n*xXQ=PbAVqnU%X3_IslNq&YA8?R3!3'
    b'0Gp*V9i)SKYu4#zXJ^BCR*TP7;u)d?$h^&ZX}fnen0B+#Fq?N4?QAsar?Y;01ld_<(^;ogbLM59)c*H9KrS!7oPGxTi|ud!@#KzB'
    b'aZc~1pW!1+)^{0oME>OEW(K<|ob%W#V63fgd_mdA03N9<8JJyHXdNop3cN{SnWeZmjcS-O!D2{<mEb@$szXP_PoTHY-d((YPsvwN'
    b'*`h@<j!=AI%r?HRip&0}QewgiVhStnlLKB}cbDkF0)e{zQQjGf2U%w{{p!nR3vR42l371@Mu*k9VpXM~sfs?Q$R9y`TD5zmaNMW&'
    b'k?j*`XDss^I|P5@E@k1Lxw=D8L97J(45>XaI`cX%hKx@*y6N~;$>Htx;&OOZ1UgLM)pK^;`%xgBRY}!#?Kd@JnVqXSxSqy*jm3C0'
    b'mv9-1wHjCk7mhXW;q}E@2WE85=H$N;C7oVRY1MzzvR19^Q*r6BVcmG2iAJ$M!PCWqHuA|W*ls*@-C6^C+=fsw`};_gIQ_k`Z=I>E'
    b'g<v#9ccERVew>-YDQxkXeLy*@VqBj8-<T|VK+<F}q#7~q-Z`^Ac?~Cn_WpenSB}|X756RIR4g7ocsf>}S$4lg1vQtEzBt30^^;T)'
    b'+)Tu=6Yg=E$dp4!HDxAYx&|s2u3nCoVX9shs`;fNd69imb4K-)QBRVol1Hkgk%|al8J~9SbW)$@`|p)cdZbj+KRt;wcVv+|hai|X'
    b'`u|MUXeih4fpSK5%cVl#y*Jq2yCYcP_A%#&x^lV^PD}H^qsRImq0ADhO3Q1gW_R+7t|?(#=N>Pj$E4Ip#SvG;)m~iM43|b1&)jcS'
    b'<r2BFEnS5IB5b+_l0*wve#IP7@#4NIqC7*Cq}1w-{nldXVZxI$=x9m3g0=5_MP^fYk|~(T$2^llu_vmfNkEnaBuQu~5Fq&2`43Nh'
    b'2@iYaI~+gVLD>NwEZM=VUdY0Yn~3$snLE!Mm5OfXI^r8e<jrK6(|v=fe_YXv;owCh0O#>mKe5>1eaf&uhO5lSTixjwsi3Zp8WdT?'
    b'M212lA6E^CG%9c0OOc1C;c#e~y=Fmh?jIX@=8A(nN*JVeu;J$qcnppoBKVQAARa30@sOy;1A`umn8dNMAeiy{*ItWH^=grhiqK$~'
    b';~&(|Mtq|$ypd<3I0GB^jB5;pHAd^%P)uV4N4Y-HA76P#!9zRl@fiq4MkNI;7ddF#Y?V&46?#z9T*38&|F|@(Ytir&GRz+lP$Y4w'
    b'W5JZMu`gjPB2jEScIF(7$4<9>FzIMqz+9XkC*z1o<oQNghRkD1Hi|ft8w&f+NYV*}N$4p$wG?LUSM3eo#^p)Qi8wCtU8=d;G%@~9'
    b'5_ZPr=kRSTn4sg$&v8yEFi(}d7RLq&PpEfHraUd1#&}c{TAC{(QcT97L>WC#W*n0xqh-g0Ra;apj7)`5Ghuj$%a0Hbig7M8Zb(B4'
    b'qc_IoU+6%2o9#Yq=29zuV6QM^_XN5Rqiq|c=*-Alv991brg-srh%j}HBCJ||tYuH~PsOvIq%C+Wy=Rr%CQ$R_e?lYvh1s(JunIOg'
    b'bkzS!+R0<s;C@^Gw!Zwb-hId*K$GT4!rGQXj9abH`eYlE-fnnwtdV>=9y9wi-8I3x!BluNgBxJp{F>t>cphVpwYTm(t3b-a*&(`L'
    b'i9p80RD+V2m!#}wT>l>2E-MYT=u{Du%Hs*^=3KxAi2l_#B4g8~XLu|WiJM@k>tvBJ<p<GEa5Mt4a<&h%-4Xz@A--j?ytyZ|U~}V*'
    b'HT+fmsa6;%a>1<;P{NdC!VFt@mjB^&G-d1jUOD8^Y~&i$OyfW)g7g-1-jVqBq{Qlns-D856Nqb{fGOR$!m7iUC$1Tod1m0_+Q0un'
    b'Rs70M%)FM3{blhK>_|!8bs^rjY&LO`!za!?+-Ni9H2L&lxyzs<fOY}cx&Z@!vj&K1@Ff83KJqfmFlNe}K+E-q47@$_vD}>Bzxmt6'
    b'YqmYlH%&G$O}5W{O1E%_^V84%-!3m$JKj5fahWHzpWnZKdpUXg?#<tSWv_hL?e6mPCr|WOg|35wU%Uq=^^Y%pV*mN&H5Ak4Uq8G2'
    b'+uLWCm$3z3Uj96J_RIU9Czo%2_?xR8Kfif(;cUArkHmWJ>){KN4|6?YL255wowOR$8ap50ea0q-D7i1JUbpEE+&D~k{I<qlAuom8'
    b'Z16&jO*Ca)hpaa_Rq6+<errVwRe+0n#^&#?(NQi5Q28}bKaRCW<@)!Frk77KkEU3J_$4gC<_f|p@zZiWTiwsI9RC2MxF#g3&_jSH'
    b'Ay#Fh-D*&Lyi!Bj{jiEy)>Z4;Unk|U_W5-~*p~xKuA?=yhc$=ny{j4uqWW%{yYwa(pDBPDe{RCQir>$(J9da|i)WZ!b-&HCCbQR='
    b'(SE<emWyRb><p)@yeF&Wbn}HBS$m!4?C$;vo3-nkFUxgvxuLYKMtqR1al0>VX0%_?yh~Ti4p`k~+c6H)7Pg0vZ&??NdF4*=Z1gkQ'
    b'3i7+f22w}fWt7#Jj~C$3V?W+)H@nSjvpU7pk}>YH>etv>{$slOlzxHh6Fqzh>)4P+hmu<c>){s6LmJMHpKw5H?3dbgI5bCjxz5f*'
    b'5Q4*M^^zUIgz_O>^Zw%9s~4}CZOD}5tGDlUCHVTy<*%3TFJ9^2{`B(A_s?D$da*$&kN@>G#LQvpJf*6q*cDn}guRf9$FH1CxNg*1'
    b'wJHM4)-nO@eFX51VXr@#XTLvL->+8DVsJ=e-{cBMn+|F>>PsM{oF-ZWupeyhcNjIn<_XNy`}_m`2g*FRhKt^A*d{R=3!B9PApv&F'
    b'+l+|?!}5L&`#;2xbCVK7z$dfSCTA7{>{sw0GitYA!tNa|8+>gfz0j&=Djen_=4@|j(^jMSIrtmo0#-J!VtZ<Lddl;nES~XB^7isd'
    b'Jor}3o2~7u`(5D0ThuZ8YTMWS9Xnlvvj1S-(Ak8|5Wotjdl&9LWIswDv%D?N`9*Oycg-RpID7%4&o^>uNDwQIt>ox5eu^AxM@l@='
    b'lY_LbPA3pbt=Ass$9{*WMR}Q5#qoN*aAJ#NJgc$d2VfeET(#m?+wTUWfTnthFEsLO>kT|+?~37Y9PF(bxz7>V;ZEc|6>+O6DmNA%'
    b'8vCzj=+8q;>afuq<A%hg`vj)l6FwP)Q>z3#HC_kA>VcLz^d1dR7-eidlWjHORx*Lfu-U7-Cb%nOi?Ji9G+YYcWA?>k_0<~Mca|}F'
    b'%1*pnu+24VkfxLP%3;E~9%Dw}XRz+?x2w}U|G-`_{A=vL>^z;$Hw*R@Z}urMV~9VOi&IMIKL;<3_)(ax;Kii-4>o+j?|uqT!RWhp'
    b'N_+ORjvBLn9)9Q2?u6O&hLRs+AVv`#QFXTSSfQjCP(Y)hY19B8DDT91?VIg=mN$-kB1AbSF1@DN<R)W<Qx5xN`h~9KVJAe`fr(hN'
    b'!Ktl#bl5ad-NInzJ3YV0m=f&QMs0z6UBtZE*ZCJS0|=#oIyvEE$oGeY`ur$EkN!Z17x8Jx!}#bC>;0eLXmZw_ym)@``u&UdFD@=I'
    b'HS<zLEk0Y%f1sT;KUGmY(ZwdB4N()aIX37|=GknOk|so`Ourxjvp(sJCUgyvPuPwilVAyx1so8Q_5e`3h@i(WkSR|tNYsl*1j?8_'
    b';XBMfK?J~DG25UhZrRbO1WS@p<s#gV7YkAfnIeC;=n*_>ghdyxtM4&$5{52ir<dh_-e<hLu%z{7J>6_pS;~|edA_iI<aQU?qG1uD'
    b'dAubM@Q5-*Ki=H46S6dP!?F-3L1`Y>IN0&a)qDn$C{}i}%_C*PHUnX&5N#x)ohBUT2aj=pcQVQEA&hUqCg?PseJrUZ23ld9su)z('
    b'>dBH#p3SE<FM&!73lgNBoZ>g<uyem-B<Fe#t%as5WPp*Y<t7DU5gtD~$(a(n&2k?2g#aNU>=YN%{aVm#U?w%)m@~<D%rbt5acrkL'
    b'aiNOwj#A;gyh0p!iE@y$CNcFtGuCTK5g5HT%Rt6TNs49)WtL&U1rM#r@9*GNTbZmp0<Tm);sTg)x-vYMN0q@4uW^DDA-s10>~fpl'
    b'@FL)%pLhFbxIe`kgB&#++u+zNUa%hK?Md@2x8A~eiTCrfEubW_)<RN0DPttN%)V?ueM02I-7S^kDVry#=ac;7@=grN$2H7G$}A9@'
    b'HrZN+3^*k)tLF2J!WVdlDr-+D%*;`~cu6dGRY6XssW1Z;OSb&9dcmYjEqVM!W^GEve0!hMrUaz#TQJ|Kj49h(R`zK8Bin8!n_IZi'
    b'hPlCdSWzeh(u>^$x?Q+@Fe*D;&$5-&zM9Mr%Q+CwvDuUD5EqjAm^wedXKRotg!wX0Z<y5z-Yd5l@g$mAx!5J=Y`XIOalM%cbxhBo'
    b'2=;;1^LyA#)9o@7!dTy|GPncX;buKq-hJ4tr5twX*xX_`IC7crQUdaTKYE+}=lv4q(T5G*k=>><J{#bkWHM#5bw=797RW9jjRS3g'
    b'cZ54SSWDqW(dBdkg87(*T8XP<de4+UNZCNhDvv7VFd1^W5FrHtHRQX^U8&SrdWT{4AG3_DnS93<!FI9&?F*t-%Ue|FU|O)Qn<Gx0'
    b'Un1=ZfNHY7zngqYsnz0+5!DF=ynbA+R^fg_{mj>aObihkkJl(q7fgAu7hs?!yUoXJokvKOaE44zEmIg3IM1MV*sLiv1O&6G5D=E$'
    b'PT4_rbDs;bIakB5)Ofw+^mmH@{kz6`%-Mbd5=0FlQd$mYma{Pe6#&tT!L@)fZgTeWJsx<qAkGI@1dpf_zoAwP&b&ft09Xc_C0}%l'
    b'!}D5^LrCDauyA15Fiw#7s~$jfs-V8)?97fU5h{=VL)~uxO<@K!>D=5aj0%NlbRH_i7hv`ozGo8>({Qj(|8bAcb4>k0>A1v_CV}du'
    b'JAg6S71b;zDm#QIc8$_sE{XD@e#@1*-dq3|VO#Q&^~dt|euXC-_WzshhAlExIFDxffy{&VtVU=YL2I=2DNad#<X<Z?K1#gafoSqz'
    b'ha-7)#;qjcDaA-Hdc>5kWHspaT(8gPhe%(V+^yL9Q(2-rtwJPI5QBa|F1npIiwPS}m`&nf1x76FAlji~jdm@cooF<c30`NPgvDTG'
    b'*m95WEq962n8%AXjywEtE_MW&F#%TEgirnDW*v|WLXC4^;og{UH)tg&+FPNT4M@f9rPnJI(sY9!KyE&(!&dBHIh%~>Z62BqY!mGD'
    b'O#%#7(fhlbZ8|3>44a_oEniX)0}Wb=u!$qb3^!}6H=I1g9N~qA8qIsZ-KQh2#6q0(*v$GplXiO1cvTB~q@q{KShWRhA`}G3tq6>X'
    b'^Is9qRsrt65p@=7sL=UE3b>ZBxA`PCfyk+#>m7vi5{p7h1Jv3U>JM;naP?hGfFjRu%L!4mBO3cwFhKd_G9?H$`dmpn5=SIHhh3+?'
    b'h_020>&5O26Hb;_K(6D-iJh4Q_Igg>>$|eKYfcX_F;FrAy~^`7#dy(L28|RkfUY7C8Vt`Rcr^e)|EZ+z6!+5;x><@C$_ZSStNlvW'
    b'4?06|;2cvsTQi+E<Iax{7@P3}FW9nnwRIz-hlT$`WHwCi`S}~|58a}olV?de5=dDfDDxw&<t{MM^<`D`Tnj7`BarC`|2=7F)n2+2'
    b'n0;jFNxmSy;WCBEk@5HxV0OwKY#>=sww&rkCI<mP<Dy_ocel~>803A(h3l1Cnan)g{(V_xgHn&f`xh+YP==>)uN*@15R`l<N;n92'
    b'B21nh3i?<g`51stB}E(oR;8?aj*?_wR>&a<v~gXucNQ6lcV};$9xY(Ltc>GCRhN}=SU6Uh^rJ-UlofJ}fPm5gKj==jR#)%!=(dnU'
    b'ngC48e3}k>qgksx==9s8;iA)@_eN*kUT4@koA<I-cQKj`7g@VC>z(!5gK4id8cpYE?`+VWcV=h3+9UQqxIPvqSXPKQX00}Cr$PWI'
    b'y3_pbyYJp*fOwza`YXuBVINBt+s$nP*!x>(exB?;u(SWohXgt*5&LvPN0(D33Pob3(Kt!--6?`CpD6UEwfo(oc_#P|FxwCSE!YD}'
    b'`XRUk0hvaj8(6@^29(FIk0gTkDu+vKM9H6S=3lfl8o+s9=IEUT{vh^j11t0cBw{_!7WH$RNfU&wc`O%u!4T>eyhhf|6A=C5{Tf{`'
    b'OgfeIEdR2eDc{yzg`(Jk1`5iR{NF&D0R`YUW<}&nSfh2~yeRe+sJzZz#m;px>^&E&u$UG!)=ET>9uBwM=72%Mj=(2ZSalfD_2wEV'
    b'LgxGr>}bq#$0y|U!Wj8$GcTT1?Mjpe02R|3&lAPDaz!OJllJ+V0~$?uk#%#<J>pG=e0-E!2k6eTE<|}iz;p2({N?OVHNVd4tydzp'
    b'Os=|OiE#WIquY3(85Yc!EKljQR<5#S#aaliZqZmCrvQ8OYB@b6_zwfNi5gzS(42nAKF^mo5Xgbu;nP*2&iH|Y2*@5#dWFv+feD1B'
    b'yR$<mZSr*ro7fMXbit22U-pIt2e&DkY+G1r@EI&}CWC+ZT=?ft*nZB$jBBLdvw3rkb!hjRR#5eP{sUb*oJirP{34=m;t9QFrls;2'
    b'ENcT82<~xNK?*Oy>u2v@{ObiFV4CUZu$STnrho!*3BD&!ITX(AN47Ka7*bNS4GOfIY)qOLQ-X@Q!z&4XZ8Q)Tt)85)ye3RN{_x8?'
    b'gz===qtw#CGPE)lp;1LN6#9RdRZBUPiFA6~S+6m(UcP=+qtWHp(=|kw69+pRFIrt4W-NQLBIO}g3wJSY{4LliVv!Kt_5RJ9mzTgH'
    b'q~Lpt89AXkBc`_-?J0mm;!!X42GfRSo7UN<b`Q=y?Y^*|yFKx#J))C77l)oo?VukEiO*-b5@ZGhd2Gp#T4_IPx6|R-XqKMMXQNRz'
    b'J)5U#)|s`lGiD48TdfFGb5%Zv#-C2Ry>`3P?Q{oe=d9HkPP5sp-_KfuMYlhjc1FGFbl5&yxS{d?r~#qsTZ)mmU?<rZd48Y0PJdtC'
    b'&?+IwgJWXChoR^FkoT~G-@vhFyGd`s8NtSGo9^~S(0@2={u_3@gX3bBZo%s(tIf7?uuV&``I(77Wd}DlGjHL_y|``FYPA<lNCa5F'
    b'xW<Pu5~s)6astsbUrc%c*D?+lp+8?-`0;t;s7ibhaU>7gB$VD>GCXtwg|FenGRMXihyAa>bQv$Vdlg^%_2rvq&x_aF^(s|1@kjty'
    b'{S|TCDNymEL0<#1uavskQX`Py0}Qpw+W{;UK&)@~0a2cH!|1wPlky3uy2}gvOu5lZ@CzqnFzs^@0{Nz9i!H6Dx%IQ{P2IRdAosIw'
    b'f6(c4dTDpqnfH2~UbmOcJ7?3`*`S?fi|(*BTeQzI_Tyl*U^~=wG@Q25vq7J|Gn_8^5!(?uvX*lW#9V82U_WbRoz|$6_FA3(Fq<vT'
    b'vQf&myzZhu91eQy=-=;ZkPh6NCpZc@j_&*fLA$IT6I^1dkrj#KnbhQXBxnV}jix)ZI$|tk#X}??X6>(P7<7P0{*EupJ6vA7nEKN$'
    b'tC8sDYF+ul$8HR_XG|j8RNsC0lB4fdMl6Eoia-TLV6V8}VD^m{fz;wPboDKNx4aD{>WvqsWAHnbrTe@RNjPW~9=lo-$GRz_=QdjL'
    b'?&8I(XH4T=i8^0bS0cP|SCwqK>uAL@?=G@=x|of!MK)>=JDt{|H|uw1)86c?GavRki?d!U9d=v8es3^OyZx*;PupFlds_41Vm_@^'
    b'SO;F>2Yuo+5@o)Pi+NJYnNwa6pP3cvY`}Zw4_WO{S+eHFNoh0ry)WJLBGOj9Y!Oz|D*Zy?@Dy0>PC#`sT&n=&4GFo}WG7>b|C%dW'
    b'_{i(hq|`4Dcs(HB6}KJem6sff0=FJ0nMGhpEN*>Z^F}iT`a;FBHxA<w5cczI7591w%pL1-CAumG%3bYz`M%{jsD!QW72?F(_dOkn'
    b'!5=Cw29;l%Reo8A!u2cjQWm0O&0QB;q~bmZ2vnxFE)c&efbx5-7!m<407Ek}z1c`7z`51!V~YyDQo#LlaZ3D_0^<u}!-q(3?Fqy`'
    b'#xG`r_-h`oBLMm*HQo;aVE^PO$o`hKC!pjl`^Y3E=a<^(aukse6eyyGo|ti7;&PmI>|N$k>Zol<tLwxy;E+=Anj49Z*WJ(%n>CFr'
    b'W6Ol<I*wijjC#LTcCT|&S7U2+k_l)`9a$|nN~4^xgPy(IOaYvM)b+Y+wNh`JoFB@YF0zl}C55Y_c<1U5K2Yq3nj9DSgV4rnU$5OP'
    b'9)$>NUnzm5j95vWbWEovtnu|D{pMn6@4c`BXOPI1MFD-f_sGosr0fVttl`%T=w!y=d>BWWrLYGXknmK)t@9su=LKW4?nE!VIDxa!'
    b'*YHtD7Uez*8C(voYa6c>C~>@#+B*A05I5{wKm&sgLaiW!h+Nsr7{<h&6m${r`NW23z~AoIP}YePthm??1;#a(M}JOso50=AqcEVi'
    b'XxX{V^Z-5V<g0M()3Q_C&=r<!`u7zp0(S6!PukbOvIBp%&pnXHoBZ@1;$=>V;C-EsPeccwf^z_Vo2>IjqJDeJzpa<GKp9C_R~*4P'
    b';5rhQQ8>uiuI~7@QqlZKKQ33<>&@;*xWy$!6UGy%)+jHcHuf1iZ1G9SRyQne_!2KXVP%%gbk_t_TycljR?@sV&BVH0GY=AbweCKk'
    b';>O8WUVBYu+tq^oi-*{mp@Aa7mjcL&j0`$#R3PDz7v*D5pFJ&8u!0!IN0x)iR}#RSsPrzVcp9L8wurQocz)zRp{jcFBoPcUzgZ@l'
    b'HNRYhD)DyQ)5DE72kWHw_`oZxo)Vtg9FxWC!inc<WEhO}pV8cLt%v1W&TR;EM7vOva+}`CW5pt4KPoZ56ioiD{J~*Q6MPWp1m0r>'
    b'zkc98wg`WX$`9hvcx7&zLduoLqd>7@pKA_dT)tU)uYR389+RC>;oN&PHo8dnrljgHl`>!SA`@0*5{bKMxP2f`BtLm-VH`XOz%v;M'
    b'>|Tvr4B+yY?OJO0_>S;Suzgv+^NPl(?dkm;2t45e6&KPt5QL&WjR1YVfD)f;*>ph|0$x9RbzzwjM{K;|bg&zbhX|vQ%6GEf=KAM*'
    b'qs2K!wPQN~J)j)6(eGBPbnrcn`$y|Os#dkBQ`|IOA#NJ{mlA0#|L(V);>C)G@Oe(U!^7iXV`^~vD$T0;<lqZ~BaX>(9OMjx0A=pl'
    b'EZE$f6jhw;&~c|*ZkAkY)jma#y7`G!bvSN$xVnU~abnnk-pE7se?=RGxv8J@H?*wu75)6hv!7nSxqScP2htATzkKukrM!N(BOE{F'
    b'j>}|7#YDgap06cyU~-Xdt7gGKP$2*jr5L;#!6lctuuR$Hfru$#a%)q{+<#oeXJxjV1OZGu<ZiqIb?kR1!&{J>nnD}-q(Y9jQacEJ'
    b'DI6QLCR=3$6iI%z^*sBG;|;SDixxGGXJ_L?WpH<goNP&L_l2_RihCf>saR@UjPMXe$J4TL0Yu9NZHcE<6UrQ4LsLEjjeSzPYBfh`'
    b'b8-Dguk{rg!CkQp{e?z?negLwOo_yyW|gS@Z4$6S(L}n&K1G#+y&hc(S2e5@!CVt62W(8<*Zkg26T2U`8%@74{#*CD9J1v28BDCW'
    b'$~&%`km?9)u+WK8n4nOj?M*-qCt(g980@PWI~z1HqO;aWyv81Mf+R;dH$urxdoNsGfoz-rfr<fbO!szZItfxY^VB3BVKX(QC3S8v'
    b'Izerx^b?Mr1a7u&8;vFc5fg_}Nq8D<&0oA%l%qbLuJTpSQ7@UonZW5JzIv{DDd~HZP>k7oHh+`Gxkoqhz`AE;eiefi*)JxeohN!U'
    b'P?1&6uc@sLV0%R-c{cjz*LAy2j*JnFZ%?QId$T9Yv9!HN9VS#q<=%p~9kmNur=<p{hh1BXLGp3emRgzkL6(Z{#Rc~yH|WQGZ9(tY'
    b'Al<Fm!-CDr!z}6aNO1%q4l6;|ZIpPc;IHshTSUKrYdXa#g?@r+lwRuYW5GU~N?qT^Og^7Pr(={l@vE^TDeeg8hD1b(=Jr!^5pLO>'
    b'qLeGwY5F>_!9>e-3v^1-&CDWxi>L>b5V7JXkS-&;FtJB}Zug;xGz&(I6)^~)t(6k+Pf^0%cDdP788UxJ`J+9eu(GWUFYo4CO@f50'
    b';`Cx!4aV{a(i8OD+jv7xyzBE)vs;ENY2>5@MZDkT6dG=?k&naeD-8EmsJ^xh*A}Yz;Ji!qoF$5QEIaY@mv#Dkx?DjvV8S0O>FxcE'
    b'G-Sptjw*6q7kjWPG$ekwy|suKe|1TeOaj;F8%(Tm#p#VNpK&}Bj(1WC9kI_e+QUQ&5q+p}e@tum&8bpW;P3>-n8gFRkWJ}|&NN1W'
    b')>t)WWGlu(#xS`TIiw&pDB{q2IA!wiu0l2M>YNa`P}DB=Ubefa>f1vYTs(z(Jxm~59I_m2F818x?bjDQZ5)N5<W+)Q%=6EE{ktb)'
    b'baiXzU<+q&C-{Drj~NH4!!F@5L0~UINCi*xod8hC1lpHzoG9bG9(k=#JSD}geT|oe6n-vRJ8}J}b|vtsJ%90TobR?LB(P3jzIgro'
    b';_s6mU%b4)-^?=5wNf)OTqIS7lU9=rJ5t!ae1Gwd>A4H@i5C}_5U!~5(}DL5$S)G)Yc7%>?x!5I`IHTy;DAhOOAb5UYyz<le)><C'
    b'Vny4Sfym^Kl``1khPh~@@yqsNXV!VV!H(&ylN#rTL9;*+O<GIYzhPpq-%kFDOqB^xH=DfE>ItQ269EAd-I#0~O1TEl7W;M#!mOr9'
    b'5RdvPtJhM!X@Ppwz=<y{&1Mrp`)UVZDr}Z;qm7~=%Av`5qCog3Dk5h+1GW^lz2sIw6OBUY4zfv84dtctIeoxf<K=p>;m%BQYqAP8'
    b'93gXj&WgGclP2~<@yuV6_e>YF^}&{5j`kRy0^7ZWR&&CB1n`(NL5#O#w}JaEKsw5j-G?jzW(M@bC=!7T5U5O6$vXR#{Cx53`Ds!('
    b'ZQu>wWwM5>kTel`A^~cIQ||%NTFUyQUS;W)CUr?#S>;;+@_6tni`x<78lduAvL+~(A2lt^*+8!CYL{9KPpqZ9Nbt{{h|s^14b3-n'
    b'$Jx)q11au!X&fbxjMF3N#gh3K@){9-huju5vOZ9K4Svco^`PY)#aCbfsn!+x&@2Zj$7O+sYqQ00+RcWG)?zs8v|IgYr#tI)M~hCk'
    b'-J1{EgYMbcVAk#oYISjrE7<P3-4UYgq@b*7#ojJB;P>#PYiFda<}~4o7wH|omHCcW+PO;Os<)lBbl!Z1lV`bE)0xv|7UgFCks27_'
    b'6TDYWyV%<nv7p)>(eFW5osK04LUkm;BYNR@QDM8*#j6#f)fQe>qQdgUoe`W$fceVFD386tkq?1~L7JZkug5|81PG#&*-uh~BZiC4'
    b'BcIe1R$;;!wE5f<Aapl);jI@v4l|-`_Y`AuwmTj)SmDhlz8+&%NJ_q#S)soVJd}w^M48Z+CKY9H_lRR~kDF>Sq<e|Y<euRCVbkOg'
    b'GWVpg<OQ93Qt-Ja8liilGrA`QrMq=w+Gagk#=>s!w<p%=Z%|E0>zWAN6UpeFsFd!BkJCL-N!=4at9v+`-&jfeFu*4@P#@Xstlt_A'
    b'(qY=mI=w+Q>Sd#|`FwHKUJRzgZZ^+43zGtVu}W|J4Dg9b0iU=y;FBN;eBxn&PfBRueRlAR^$Ap(Phv5Eb<Yv{FmCunki#dO9iA&X'
    b'uGcJn_{2>RpST#}6P+SHiQtG25S%AYhI5-=-c-AX@XK>r_GAx6cQ-YCvL83Sq?XrfqVKcZ+8}gdNo$6H&IPEh4xPKr7HmT<XJrr3'
    b'=_U@E+(aY5O^^W>8E{m_TQ{DSPJ^4+Jh-3bPdW>3augceZ?o;1WVi`bKsanXe7MO$-0ty)UDS@-)^#kWqQ^OMb<*Y*1KVxfCPn!J'
    b'ou05d&i4#cJf>yDoA=K<9N;q%m2|2F9m3iH+l_aS8u=(czo8~6$%a?yg;^)c!*Q+J=%K`hyxNRgj5sL#kIF}(Z#Ig&f=&+M;89BL'
    b'aml3~4h4os`QYJ`+G!kJAM(<$p&!+`GsJT}6twa5BY)+~YxaaIau$JO!Ov3`KM?N`2;J6+4h~&yML<ZKUId4Co%fVGW4E$?gD!fA'
    b'6W?ADrB#-QaPGb35X8?Va!M3hw9YtV;o?fZDFB0?6j0?*8Ps_ebydm{$R`<b#XTs-uYdv%!ul$<;te<W*Kq5DrUNc@`XrFxrHKpk'
    b'xuy(X4IaTC3j^bk?o`I$JvAMcm)Q`7D|xc2WSB0+-+#voZ2aeubKN-PPiyG3m17MgvnSsnR75uauFmEq+--@ct4OwM&NF<Izlc;q'
    b'{Gxh|`AeZv1<pam%EzZDUwbm1`FQ%QUVqv-I7idZBH`RWHAVWbD^L+(#0&D(g2Emt%8;RlG8coHFFrsyiB|3gF@5{y-TP<Xzr4^;'
    b'O!t5wm2z}cYu2_!dzMaz*<#d57c=(%`E;K3+U@x~8@8vtbkORbbz)Gh^%8hA&#>PgjOM*;Fh9%Y{aL4*Wuvn}zdh)sXY*Ej*2%iP'
    b'LAyN&$*1^YvlIcBd$JFZ@wY-Vt`5vxuaXT-;9(GIW(G+TQW;$r!C&k+)+C&@NI)jXysMZ@U6V7rzz@r7m6E9|;NK}-p$KqR;o1w?'
    b'W=DsWBKGn4s?riINH&p;1CdgI-u}y4U^MeEp?V1n9Uok!Y?&7dAa|U}m9XC)1J)f+o%iRUyU}~am^v_fA1eL4L??Q3%nQ~?N>fxB'
    b'8p&^j+^cv>1llFG3+$Gh1p(qYW_EOtksB-P71GascmwRJ7^V+VPILExRkn!`uA5bpj(QSG-nfiVSUuz;cHW>PXh2t~_MpfNA>)Go'
    b'DgR|p7LP)-hBgw-&+)KLBg>fAPc8RplJC;nyW&R=T$Q6~VKk?w1#}a=OW;jdnvUEgzY4%M?UVW)IlbL6>%6^Q*rGqHLi?eA{n_33'
    b')HQ#!^HX#tHKu46dt70rUHtgw9nS(X^VR>jJ2#_y^v-)?VAR<lb^6l#`Y0-~%E)RWp$(DFge?*K&~*h*T;XQ$WS(Mb)8qZ~yyejA'
    b'p+I!Esb-XFX|(lv!<E@xWOeuAQ@MEtH&5s;&)=S=^D%Dk*z{0D|9D&&c<e38*e=OxhIcS?n!RwfydKkk>_ll1Oja(AQop%4ned%9'
    b'7p>-qCw$jhwZHaS4SJ?glH|?I9%u|V!swkqF7*CWi;3nlt8tWc<~^sHd9sD`#zf=!EqG;%V=n=xQHCDi1qzdjnPUP*&4%NVU}%*N'
    b'K0cpRi5c)nhln+m52uKG_vYUeto_PR`!T#?$N~@xuHQNv4hEyvU^p73-4;6`XKANB?GL*1L2KAqEEZ?&tl#TSr|sT+J{yd>XX$9#'
    b'&sx21zccC%hP4Of9O-0PZ_%2kvq86&4MxLxyEShO`lEi@PG_C|aNcjtd!xlDTl6~ZY%yB2X6=4&l=T<vV83Xc)k45^!iS`LfiP{B'
    b'Aa3dSLO{0H(zRE3s2+J8*q=oHZAef(%8BIK=)>c00?0{{O0vn7N&CpU4S++WJ8C_8>IrN~I39YJ4sGtDW>johkk(twD6SRN$Lrp-'
    b'A|TR{PEwETOw7Xo7y{n0#|r*}J{q>CD>jPLfxn<-s<DkOg-z^S57>QNo5Ht`m0PFB!J4bE3ZkpM00wID0jXx4yq)2yrtMjIY+x*~'
    b'nQhll%e!KogBgFAb5*s{X2PC)_~o--FWx!)Gj(qzDgYtab@LoV(X<_xndp&?_S*2UI1aPioxlLP8UJ|t80`1Q(t5W{cd~~n^q!j5'
    b'P-*m?m<nU#-0^s;gE>(3w>pf&5m3X*aUC9qCcxF*wbrqb01vUi4v$^14i2{4x<8xUiN>3KA~W(%tn_wo((X^X?B64vomViHbKd)v'
    b'O+piEg<D}VO3q^-##hgHBqi(vbQpUKa%Wm&nIAm>yufdom;qP2Zcvq~zDpz`4cb1UUzRP>p&tSZ?J$sv2#g9hvV;JZfNLzC*JMCP'
    b'XqO@qBci5EMmQ|{@E!y+t~SAKr9wwOeYP2kq9o;iJT|QaKH%ZpezqBjq<+3&u_|Vkz4Pub5*Wnc3?Os|XMsFCMl}Fx3t_rAK^+W('
    b'2|A*(c_x#vS?%OZI4@8a{#t^$AT5gsEP;yqjn|jLFODqpg!;33%0H8=UP!5<^O%zTotI1zVnwFEd%!WzpVIvOS^kdhbAV|mqo}UW'
    b'^T@RPqN=JSo|3O*<j3`c+S<K5jp{}uF088WK#ha)6RU4cM)sF@-@<KX+j<dwX(Kj=k(x!{k7Hn(4*^V$#!Ie*iyYxH@E&)au)3l@'
    b'g2sZ;53W5rq?#J~3u<pT0ypgA`Pg%Af*c|Bu=D^eH-dAW)=8sgw@>}jiyRGpa1UrSIE4u?dK`v}K5!baaw<)M;{re*aljm@&2)eW'
    b'rZ%gI%%m{fjs|nly4(zwf1yZ@MGVIx{n(j(?6LD4Hi~MjWrc&tnRg7&W6qap;sp?$4oN(A<{cl<G;d%qbZKOAabX2psl^EWe?U@k'
    b';Or+;iv2HFO(^C&MM;Q!Sp>Y5ON^bcgiK;V%q$Xzc^)zPiI3GUGIgZ9Um9k7wHaQGUm5ANhj(C1mWYxi3wd>8cWNxN3^C*IDP`XU'
    b'o}vf*Rgj6No%8F))m~Yj{uN&@DYtXo7_{n7^{h%YnN?&}nvaAMJ$>)E5=*VDO{<<-dZRC45b_0|+DVRD?t4R%WUQDeIM;Bs2=kM2'
    b';wBIa14)1AY@#F}Vs=_>ayO~5%mTE>gDF3Azp0k|1E@-L^bD;sE$IiAcq3}FuC$a$HK+5^bR6nO?2)NG1>jsiwNfMLTS$k5+jN->'
    b'Nnfj}k2cTLH_={ZVj{IsPego}E|1Y*Z4=N3(fMEiPTHtd8<;r=pZ<)_D^vYc-|K&p&g>YmQR&>y7OR&6P>MAheoZ}CmAp~v5{vdb'
    b'N*go6YNIP4)&~#byNIx%9%v#2QCj%%<9U|Pw(PLNEMr1eD$Tw6?z``bg95qEpP<Vm;i0#ABS8x_$$p1zXO<<K1vrur#tdo%=>klO'
    b'+^RGzL1XK=1H8@6J>sRY^T=+u<(JsC$-Joggo~(|;C#zPA%TOY!2{>=+fx9zTHmYZz@3OShOpI$0A!^eO?GnrJzI+)<h*Idp13N_'
    b'i$Upz!7!iyz^f;p5EZUJas@LNkAbhD6aww}#pMt0Uc5yjZ^vb;FXGqn(4KM4u9#-EQqghEp}0e}&t0T@T7gFFX}yu0IjDa&yTbd&'
    b'l-H7#Gv^aidQSwV8LYW!I{Vm2{@O^ub22s~PqigA+kD6fLyWE6?Gp&qV)FBZF8&g(DwA}bD17D#ICA8oQX<13E$4K8e|v`qMNzRO'
    b'zBKLtKn5z6G@mV(G(Hv*fsI2Ml?zn&hvP0`lI~DnF!P8V1oTr{@%`z==jHBl$2#u>^<}=pe*8^$<pxq;)uBZvTum9ED|PA0Yw7yF'
    b'^5xViSS^Dga=d?KbrkFeHTdiZ^?CQ~-%9IbguK<QfDM?rwhx_6O)tHur=9L@cSHktI>e4ShFQU$g{TBRcTOVv$VW%YnpLm6V$8&1'
    b'J~5WLc^hCQCbwH>6P{*-r!JY1OgS~MO86;lmRgVtKvy<S)NUJ2DIk@{w<#D{Jd%m6eYK&7Wh*<itC1fH4dk_9)kO@>)>%M=|8?F3'
    b'CZVK=s&Sq0QfypjcQ`#uJMC81Z_iq@)}S*Q^cLBCF>m(<-F7$Ych5%s#kAA!FM7Q}e?IMI*`l>*rOc+Ck4D{ys8bPYv_Zzi+NeG1'
    b'4zp}H9SugU=~-)@wR*#J*6B?btzqwMx)}9m{Z<x?XFV)C9eMF8N%tg@8e;w3?4F}hQhhK`R8<o)%{D5`6{}9N=@KCTWH`46Ltujk'
    b'M7A1b1_7<@b@qwwqumGs$6J>k6ai(OSZOelX@x27H}78j1Rf`N{>5|FT`%6hxVSW-$prKO7Ir1xzqaiIcZQ>k1QH*rXF3L(=S|Q5'
    b'|L_U_r0@y<O#u>=X=%o{JK?f#nEGc2ffK~xQ+2}d`^o!@%lE<>Ip;hdgI+~Wfhc=nzp6pBq^wwFvV&m7tdPid8`5cdTpOwpk)Ugp'
    b'Kni9D7Ra)(kP>R^bhrm*0GxG3!|t><WVUaw-I<Qq_CD%oqjcWtwuYm#blS<%e#B016(aasrc7G5(;l_6#jra_N9pja)$5+M&RF5S'
    b';b7LEcG5H()#47i)^Q#dX1nBFK!x<aA0xo|@~<!7JbNxH5wZh=<-@dc{;UT3){ib-uYdAizUP!6V%}esrh+e=9*|mJX=$AypH1kR'
    b'=}H+O3k^j1O${2?e=*5=LP%h0Vb9R~BL0|Pi?`Kh6ml7}6zGB;p!l<Y`i-Ou{~cYI_paB~BQs~5CuCNyP%Md6no~#-YT}Ys{2H3A'
    b'_qVvD@KFVpg7OaVTbKzY#k1B7`sIBkqgd2VE9oewA>D9S$OSo(EpI;TWJ)7H@k8VcFb|2_e0g?edjna#R%{$TJ}*2Ed%E~sr-HC5'
    b';U&ka4#NXW{Fa{Ki}Z?^sc$laRAJM6$~^|6x<xwYQ`aFRHf=P9TOuMQJTmE0We%lhYL3v}vcolqZP+BF^?j>p`4C7p59{2&p5z25'
    b'+3AXLj3{6Oc$)hmg!oR?tTVZfKwsJg;+Kfg;b=r`A|sL#+ugueGkHn<0HaPUCjoJ!VKfnZ({Rc^ELuJO>G!_i%tTx&L2Ah%pS(%`'
    b'K9DDmj;o0C<XGe(>>|-(8|O*W+WfvL2K%Y#xWk}~ER3b$RFhZ@A<L2m!{`@RLi}n;`@J6!7A3?4%W^Ag4^);b#yC(GCxeVBi*l9#'
    b'KETD7sf#tyx7=b6$KFyvvZ6ONQHVY=Ri!}4)x!gBmD`ve%q^s5-Yh0`No+uF30I>~pnxC&Dl<=S0dXtcc}yWMC*Sd{B|SUqxL3*t'
    b'f=HEEB@N1OsX=Ep;dK|%OJxu$OTsZRsch%F)_Qn5U;cx&%=%giWxKyDiJm<&7}indQH9|Xd#Zo%j)AE4ty@(XMXrYFhWzOb9zuLb'
    b'T+4-WAQ(qp)VmY$sNBlPGTPSTs!Q;i<GjjEr_yM6Ynk)V9^PXTJ>@Tn60fvNR~aAZ-`2Gl9iUx_{h8CL4CL%#Ltyl+Y?Y-8+@8|)'
    b'45#KK|8hIsK=3^*z<jb?V_Y0yAKmZpBgn$5ZrbVWDC3B&?3?X5HqaQhrvyEY`?hz>H8QLyY`CYm^AIEqOjs@s0}q2Iao238m(SIr'
    b'{IjAAGf#p1Q{;tayhoW)t;Y19gV5uTwqo|e3M}bpYln%R9U=N;1prA4va*0bc$H$O9SUitt7V$o%1#u@W<Ep<`o|w_db?*2h?C?>'
    b'p$UE2tof{;sPIR354fTsJ-u3~E98UjbtB9%NKcZ$vW~b%do>9~%3~%ETusMVNshydIB|)?iilNQeVK?TNQrefxdTAw+w>-L`FBdS'
    b'xZ*{PT}H=p;}AL?h6=z(#dBNrK#B%g;g$tE$ZfoFr)-cFSlpLuFWRpJ6`RAQ>JQ&D9I{VsFKY3w>Tb0*Pw0G9j;Izncj5UyTZ{~N'
    b'od6EcgiW~#zxtn#p_Kjh9ehQG@$x|y;k$85iAVNg9gLNuU`EQfpsTSDaj9^kHgWBNED3o=){@fZu%DDX&`m(V0k<dpMF^(}4Vw6k'
    b'{t!PA{-5eaoo_cl@>}D+TYP0cuT|L24qJQ>OH*~FJr$Ui>~(fl_qt`3UOIPr?xinn&<nW(mG0H$$b}K%kt;^!+_N$xs-leMxpRd^'
    b'RD|ZhxdsRc0ZrEtE?=pE3O!dZ11VP@_1{A1<>9P6CqOVgao>Jc%v}CBcWj@;ST*uqz?!^F6r0-e_d=;BHK$+nDHYB=oASK}bWk2o'
    b'kCDZqAV_A2Yr=Xp=V=Zklmq4#RWSgxeHU34hPKw0yYs|_#>Zw(DITA76#Qx?Z<GRQ128CxMKDhfp0;5evH2yTT~L>E-!AVs4g`ZY'
    b';N<+Jn{F8999JrB0lP1Ewu?6!yqv2}j;*DPn0>;OBey5PVh9=>yK-M}aCLejXtS&CDsppTqJ(P!OT__go_#K`!r3FyVBrZz3r}id'
    b'$AnSRuMlDPq!Wz~LcG`!<AB5icZk@Q5)g2D9Z|*QR*LUkD|;(_VFQgP0%=^M`V4G_wD(x$xRJ-@e$+7D0ASi647qkk24hg6ZG5$}'
    b'(i6I$OJZABjB+sy;<idFEP$SFzG$f+(I=#aPEVik>4dT0ex!A6<IomD1J&0UYsMYTd{6n!AHa3U(ieALV)gH3h})=Khw6jsD9GP^'
    b'_ua*37;-j8phMWA{fT{)uRl%Jn`Dtrw>T;002i=IBnBIieX`NhlJUxrm6LEVD)ecAuWZ0wJ7Y^@F_x1ukYzG4X>y)>(NPI}2&y?%'
    b'$vqX;&+-Q92t*k7Yd{crD;O3YQSDGy`kLYd6XxwGkeY{6*$A9X9=K-GG!DS#s?GC3ILCyY)&q5`faC0`vIorB0@$_97oJ92p-<{U'
    b'4OObG9w2+*KtzB)J5A3Z(XO;pblcR`+b&dO8Ovk#4zFl{iM8%PYYiaI7oq!vS_~9ol-me7QhGQ)UL!Hfn0?ERt@F)ox?EdEFyvk4'
    b'`jJ#u>LHR~e7OiQQJ}wEa9lo_kE)x=DmH|It(*j)EfXEvQYv2`z;bcca_pD{W$D^7OFS{LNXxQ%RbJ&l%W|`bdRJ|hj)+{Q3u2^u'
    b'P@Iz}80V@G&PfEEuqE>kMHLYM5&nr@X<Qqg{p4#PVE>P@9GD;<svk-;pu-%PFo~0LTz;)&2`F!UwL(x)&xnf&;<)F?RtUi)x$g1E'
    b'jkg&Tc=3hOu>tyaB8)dv``}C9pqFUc1*N6<yTB?I-@vFhMcgU=Vf?0xuzStG=QdeO<;g^TBQU$sJ162`+ww!-SqSfjE<VQpXpgV}'
    b'!~+Jo<T!@5H1SmF1{=q2Do5x^LeSua1EWL>d(gq17H*-Z!WiK^PLfc<lMqb!K1-(jz^_dRPX#zel3|qA7OLUxL=X3P7p&q6+YyqO'
    b'ae(oI$br=Ww?QJnlE9x3gSOq}usw=}lGN(^j##*(BgRo(apA$NsNd>wML+0Z9`i&gA;62e^AO|$7T&%=h^j^H=Zk00%@X*92baBw'
    b'kge=z5wP?7nCjsLf`QXVgP*q<k=40DgT5~Yz3#H|%ZF*^sDJA^ssI6Vp9FC369T$V{7CnB)uA5j>Y!t;PQ>OFQl-FUF7`J6LT!|v'
    b'rnJj+u}eD46f9BQDxFqK^%B($H)!$H3(rp(y1zO``qJYF|4C(tf4@fn3#jG=(CbuK6`rUt=NyZ3R)?7hy!URE4|fvy&*fg->$JCT'
    b'$j>oOfx2a_-@u2s4KQC}w`6B|^~!6|7bN3^f$60>NW>&$HsC|E9VF3o2fhUzL4(jpDl-rGN~^?3knB%Mun(8BcBSkB!j}VE>US`P'
    b')N|+`ml@&KduoTd!5DlU?@W#!`@O1V91lnAEQ9O8=OKZEoU1>~9}3zBUuSseBoddK!={d~11bc0L{hLvKr}^=KSHQ$e0+@m-d|Ui'
    b'4hqmsR2vYPq;C;WRPB(0xdK1<i7VV4gfETp-+y`sImj-AuQ^C}@!fady`n2PLiTS$@JBKwr}Q$*lg)bd<!Q3}kmVU}R(W!lZP_r~'
    b'!X@20+kM(>KPJeOpdrrc6dI4p?uBd>>$?<kFg00MTR`4fTx_|?HL7v6YG>!H<}?(G7wMfFTDiVsw`+4M<nBea;pW;nxTO~3M$yx}'
    b'AOINVq^V@hMe=Ys<Ddl-N5T88(Q!b=3rte5jBxgG#Qpm%#)ns9rSMssI$uZV{i=)|Qo(b0=@39h5MJ6z+yT9HpJy)Sj`e1}1OQL='
    b'9qc3uk;er32)GIglznUAa&wx4y#1jwB%CYp0ZmrRX4=d%CJg8QPd}GG<ueVCwc&?1uYY{;6Z_9Euit}^HcBmi_}j&=lNS6?umSvx'
    b'3nxzQzdn2U%LNGtG=e>UdHFLg(`T=r!^8LTL>DOM=lAd50^7vje-#xxfAWNl3&bIxF4w62(TT&JyDWY1YZy~ZJ@qK#wa;lw2j{N<'
    b'k1Nso6BDjKG4c8n`mzF9OO>?~gVCQTApN978nl(MDefj_@r$STPdP71L(%{E1FF;JY6Cf__>r?w<n$NVv`yG*`E#tOAdHb(TIU*o'
    b'U;_`+?rhhrIm7xn*j40jFkor^@huZKu0?xZ_}k`sR0M};U@De!x83YEv(4%hqb<g`R}=-wUy&b&Ka;LLrC;(2C1DTpk=itO=}j*G'
    b'z&PwCKG1~yntqTxIQ%Kr!24~UHJRynyP4mwvMQzTL+umav{rA?o~6@awitEN#f<%bKAmU1c6&b0hV5xD9klvqomOx<Dl@Ee-eYs@'
    b'WYFSCD9T&u0`8vZS&dUCj0gqqAxt88wxCB}K70KWD$O^qE`)M6seSY<;`N)$UoYQZyo&7?_1&LdzWM&yOCj*t<=@^uyS#)yVLuRm'
    b'ehr~ovHJV?hrsb4^{QSOc=5?R`~AuKezmG3K=uTPXqUf=eH>jJS4-O9HgMpbFJXu^j<LF3CI2Il!*1F+VBZu9i&-zEJ0@J4Ql!iM'
    b'?t^X<67v!d9>@7-nl~S_FLe8CX+u**T5Iu?*;`xmNoXqXgU<w^XB=x<e~&-M^w($H6oAwy&p+5!K|yomDoiCk0x|sW<pR_M>%4QY'
    b'pyjVZ-@^fv--ffTm-S$N3eUl*jc;dl7j+f%;(5uTnLRUR{~X^ai8f435~c*|WN|X+q)dCB?)R`;qHUM9Yi-=G!Jy}5ArIMRv4E>5'
    b'N`By+WC{_PwEbDHY`=u_-wI2H3&n^9l4*LQ*jIP=gxP%3=4PID!NrA9a*D@3Y<GIvJEAOlNr-*OTZbb}IaMU@nSc7}<sYq%mAMS`'
    b'GYF|9PU&-;jT9q<k)|Rx2-w=;F>zq!E)FM39dPUM-$6HrIj~$#dU31nzcY-d<1%6vqV7P$99*R#36<r>dexxpJ;cX5<Mu3|=nw3i'
    b's!l>3k{)!In3yGLT?#>)GUr?n5DVlkERC~@_pXJ40YvRXx6-;}u*6B%>Un~exO|hK&8<*HwZ`H@LwI|~Ou#-`7W&kmH}jC*hC@J9'
    b'_SC-78n~s-0gvWIzboom?$4thQrJk5(~8-?lbeiHni-7$C}AIU`K4jH+N;k=p;_7318P!5Q&-$$ZOYQB&f0Ih`TDp|pO%mbK6=Dv'
    b'!(;*njmZS}<jDl$_$Lz{)FE$p;9K^}{{e148mI'
)
ORIGINAL127_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity', 'NativeC2afBoundary.test_original83_complete_method_sources_are_unchanged', 'NativeC2afBoundary.test_new14_old15_history34_history19_and_original65_remain_separate', 'NativeC2afBoundary.test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources', 'NativeC2afBoundary.test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted', 'NativeC2afBoundary.test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape', 'NativeC2afBoundary.test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation', 'NativeC2afBoundary.test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse', 'NativeC2afBoundary.test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks', 'NativeC2afBoundary.test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks', 'NativeC2afBoundary.test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory', 'NativeC2afBoundary.test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer', 'NativeC2afBoundary.test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport', 'FixedPublicRepairRead.test_present_exact_3393_never_fetches', 'FixedPublicRepairRead.test_missing_3393_uses_only_separate_fixed_public_bounded_fetch', 'FixedPublicRepairRead.test_3393_network_failures_and_credential_configuration_refuse_without_retry', 'FixedPublicRepairRead.test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail', 'PortableDiagnosticBoundary.test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings', 'PortableDiagnosticBoundary.test_exact_f04_selection_source_and_four_path_layer_are_mandatory', 'PortableDiagnosticBoundary.test_all_four_actual_current_files_and_both_tree_authorities_are_strict', 'PortableDiagnosticBoundary.test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk', 'PortableDiagnosticBoundary.test_new4_and_published14_15_34_19_scope_cannot_be_relabelled', 'PortableDiagnosticBoundary.test_portable_receipt_requires_new_identity_before_original65_checks', 'FixedPublicNativeRead.test_present_c2af_never_fetches', 'FixedPublicNativeRead.test_missing_c2af_is_one_exact_bounded_public_read', 'FixedPublicNativeRead.test_bad_c2af_identity_config_timeout_and_parent_fail_closed', 'DescriptionRepairBoundary.test_complete_original108_methods_and_decorators_are_byte_identical', 'DescriptionRepairBoundary.test_original108_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'DescriptionRepairBoundary.test_new11_old4_native14_15_34_19_and_original65_stay_separate', 'DescriptionRepairBoundary.test_all_eight_current_payloads_restore_exact_complete_7b_bytes', 'DescriptionRepairBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'DescriptionRepairBoundary.test_each_of_eleven_current_files_rejects_missing_old_and_same_stat_bytes', 'DescriptionRepairBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'DescriptionRepairBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'DescriptionRepairBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'DescriptionRepairBoundary.test_every_before_and_current_tree_requires_all_eleven_exact_modes_blobs_and_types', 'DescriptionRepairBoundary.test_new11_scope_authenticates_old4_native14_and_all_older_domains', 'DescriptionRepairBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'DescriptionRepairBoundary.test_description_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'FixedPublicPortableRead.test_present_exact_f04_never_fetches_or_reads_network_configuration', 'FixedPublicPortableRead.test_missing_f04_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPortableRead.test_f04_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPortableRead.test_f04_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPortableRead.test_existing_or_fetched_f04_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPortableRead.test_fixed_f04_public_object_identity_cannot_be_generalized')
ORIGINAL127_SOURCE_SHA256 = 'ab5dcd8de4dcafe7bacbd79155cd0c5107bc1ffeecb01459ec4adecf973d0656'


def social_42_test_source():
    """Decode only the fixed, independently authenticated complete 42 test file."""
    import base64
    import zlib
    raw = zlib.decompress(base64.b85decode(SOCIAL_42_TEST_PACKED))
    if (runner.hashlib.sha256(raw).hexdigest() != SOCIAL_42_TEST_SHA256
            or runner.blob_id(raw) != SOCIAL_42_TEST_BLOB):
        raise ValueError('Changed complete 42 historical diagnostic source')
    return raw


def original127_source_blocks(raw):
    """Bind every original method byte, including decorators and body comments."""
    tree = ast.parse(raw.decode('utf-8'))
    lines = raw.splitlines(keepends=True)
    found = {}
    for cls in tree.body:
        if not isinstance(cls, ast.ClassDef): continue
        for node in cls.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
            identity = cls.name + '.' + node.name
            if identity not in ORIGINAL127_IDENTITIES: continue
            if identity in found: raise ValueError('Duplicate original127 method identity')
            first = min([node.lineno] + [d.lineno for d in node.decorator_list])
            found[identity] = b''.join(lines[first - 1:node.end_lineno]).decode('utf-8')
    if len(found) != 127 or set(found) != set(ORIGINAL127_IDENTITIES):
        raise ValueError('Missing complete original127 method identity')
    return found


def verify_original127_source(raw):
    found = original127_source_blocks(raw)
    if runner.hashlib.sha256(runner.encode(found).encode()).hexdigest() != ORIGINAL127_SOURCE_SHA256:
        raise ValueError('Changed complete original127 method source bytes')
    return found


def social_test_inputs(selection, current):
    """After checking real current15, build a bounded physical42 source view.

    Only exact, authenticated predecessor payloads and the fixed complete 42
    diagnostic source are restored. The runner remains the real loaded current
    implementation. This is no substitute for a checkout or Git scope evidence.
    Every remaining historical input must exist inside the current source root.
    """
    runner.validate_social_selection(selection, current)
    restored = runner.social_predecessor_sources(selection, current)
    old = runner.social_predecessor_selection(selection)
    old_selection = (json.dumps(old, indent=2, ensure_ascii=True) + '\n').encode()
    if runner.blob_id(old_selection) != runner.SOCIAL_BEFORE_BLOBS['tools/targeted_native_selection.json']:
        raise ValueError('Exact 42 selection source not restored')
    old_test = social_42_test_source()
    if runner.blob_id(old_test) != runner.SOCIAL_BEFORE_BLOBS['tools/tests/test_targeted_native.py']:
        raise ValueError('Exact 42 diagnostic test authority differs')
    contract = json.loads(restored['tools/run138_editor_readiness_contract.json'])
    paths = set(runner.BOUND_SOURCES) | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS)
    paths.update(runner.STATIC_REPAIR_PATHS)
    paths.update(runner.PATHS)
    paths.update(runner.NATIVE_PATHS)
    paths.update(runner.PORTABLE_PATHS)
    paths.update(runner.DESCRIPTION_PATHS)
    paths.update(runner.SOCIAL_PATHS)
    paths.update(contract['feature_batch_sources'])
    paths.update(contract['feature_batch_support_sha256'])
    paths.add('tools/run138_current_source_projection.py')
    temporary = tempfile.TemporaryDirectory(prefix='targeted-42-inputs-')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name)
    for relative in sorted(paths):
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if relative in restored:
            if restored[relative] is None:
                continue  # A real addition has no historical file or fabricated empty preimage.
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
            destination.write_bytes(source.read_bytes())
    return old, root


SOCIAL_TOOLS = TOOLS
SOCIAL_SELECTION = runner.read_json(TOOLS / 'targeted_native_selection.json')
SOCIAL_SOURCE = Path(os.environ.get('TARGETED_NATIVE_SOURCE_ROOT', str(TOOLS.parent)))
runner.validate_social_selection(SOCIAL_SELECTION, SOCIAL_SOURCE)
DESCRIPTION_SELECTION, DESCRIPTION_SOURCE = social_test_inputs(SOCIAL_SELECTION, SOCIAL_SOURCE)
DESCRIPTION_TOOLS = DESCRIPTION_SOURCE / 'tools'
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




class SocialActorBoundary(unittest.TestCase):
    """Synthetic source/scope controls, never evidence of Apple execution."""
    def fixture_root(self):
        previous = getattr(self, '_social_fixture', None)
        if previous is not None: previous.cleanup()
        temporary = tempfile.TemporaryDirectory(prefix='social-fifteen-controls-')
        self._social_fixture = temporary
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for relative in runner.SOCIAL_PATHS:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((SOCIAL_SOURCE / relative).read_bytes())
        self.assertEqual(len(runner.social_predecessor_sources(SOCIAL_SELECTION, root)), 12)
        return root

    def repinned(self, selection, root, callback, *, deep=False):
        """Synthetic coherent outer/row pins cannot replace an independent base."""
        raw = (json.dumps(selection, indent=2, ensure_ascii=True) + '\n').encode()
        (root / 'tools/targeted_native_selection.json').write_bytes(raw)
        import contextlib
        with contextlib.ExitStack() as stack, \
             mock.patch.object(runner, 'SOCIAL_LAYER', selection['social_repair']), \
             mock.patch.object(runner, 'SOCIAL_SELECTION_SHA256', runner.hashlib.sha256(runner.encode(selection).encode()).hexdigest()), \
             mock.patch.object(runner, 'SOCIAL_SELECTION_RAW_SHA256', runner.hashlib.sha256(raw).hexdigest()):
            if deep:
                pin = runner.hashlib.sha256(runner.encode(selection['social_repair']['payload_changes']).encode()).hexdigest()
                stack.enter_context(mock.patch.object(runner, 'SOCIAL_REPAIR_CHANGES_SHA256', pin))
            return callback(selection, root)

    def test_complete_original127_methods_and_decorators_are_byte_identical(self):
        old = social_42_test_source()
        current = (SOCIAL_TOOLS / 'tests/test_targeted_native.py').read_bytes()
        self.assertEqual(len(verify_original127_source(old)), 127)
        self.assertEqual(verify_original127_source(current), verify_original127_source(old))
        self.assertEqual(runner.hashlib.sha256(old).hexdigest(),
                         SOCIAL_42_TEST_SHA256)
        self.assertEqual(runner.blob_id(old), SOCIAL_42_TEST_BLOB)
        self.assertEqual((DESCRIPTION_TOOLS / 'tests/test_targeted_native.py').read_bytes(), old)
        self.assertEqual((DESCRIPTION_TOOLS / 'run_targeted_native.py').read_bytes(),
                         (SOCIAL_TOOLS / 'run_targeted_native.py').read_bytes())
        self.assertNotEqual(DESCRIPTION_SOURCE, SOCIAL_SOURCE)

    def test_original127_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines(self):
        raw = (SOCIAL_TOOLS / 'tests/test_targeted_native.py').read_bytes()
        found = verify_original127_source(raw)
        for identity in ORIGINAL127_IDENTITIES:
            segment = found[identity].encode()
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                verify_original127_source(raw.replace(segment, b'', 1))
        segment = next(value for value in found.values() if 'self.assert' in value).encode()
        mutants = [raw.replace(segment, segment.replace(b'self.assert', b'self.asserX', 1), 1),
                   raw.replace(segment, b'    @unittest.skip("mutated")\n' + segment, 1),
                   raw.replace(segment, segment.replace(b'\n', b' # changed\n', 1), 1),
                   raw.replace(segment, segment + b'\n' + segment, 1),
                   raw.replace(b'\n', b'\r\n'), raw.replace(b'\n', b'\r')]
        for mutant in mutants:
            with self.assertRaises((ValueError, SyntaxError)): verify_original127_source(mutant)
        with mock.patch.dict(globals(), {'SOCIAL_42_TEST_SHA256': '0' * 64}), self.assertRaises(ValueError):
            social_42_test_source()
        with mock.patch.dict(globals(), {'SOCIAL_42_TEST_BLOB': '0' * 40}), self.assertRaises(ValueError):
            social_42_test_source()

    def test_new15_old11_old4_native14_15_34_19_and_original65_stay_separate(self):
        self.assertEqual(runner.SOCIAL_BASE_COMMIT, '42f69c95bb2ade207eda478e87c602b01ab6d30c')
        self.assertEqual(runner.SOCIAL_BASE_TREE, '5ede4997df2f0c8a6910d6f4a0506e409bfcb448')
        self.assertEqual(len(runner.SOCIAL_PATHS), 15)
        self.assertEqual(len(set(runner.SOCIAL_PATHS)), 15)
        self.assertEqual(len(runner.SOCIAL_PAYLOAD_PATHS), 12)
        self.assertEqual(set(runner.SOCIAL_PATHS), set(runner.SOCIAL_BEFORE_BLOBS))
        self.assertEqual(set(runner.SOCIAL_PATHS), set(runner.SOCIAL_PAYLOAD_PATHS) | set(runner.SOCIAL_DIAGNOSTIC_PATHS))
        self.assertEqual(runner.SOCIAL_LAYER['allowed_changes'], [runner.SOCIAL_STATUSES[p] + '\t' + p for p in runner.SOCIAL_PATHS])
        self.assertEqual([len(runner.DESCRIPTION_PATHS), len(runner.PORTABLE_PATHS), len(runner.NATIVE_PATHS), len(runner.ALLOWED_CHANGES),
                          len(runner.PARENT_HISTORY_CHANGES), len(runner.HISTORICAL_ALLOWED_CHANGES)], [11, 4, 14, 15, 34, 19])
        self.assertEqual(runner.social_predecessor_selection(SOCIAL_SELECTION), DESCRIPTION_SELECTION)
        self.assertEqual(SOCIAL_SELECTION['groups'], DESCRIPTION_SELECTION['groups'])
        self.assertEqual(sum(len(group['methods']) for group in SOCIAL_SELECTION['groups']), 65)
        self.assertEqual(runner.validate_social_selection(SOCIAL_SELECTION, SOCIAL_SOURCE), SOCIAL_SELECTION)

    def test_all_twelve_current_payloads_restore_exact_complete_42_bytes(self):
        restored = runner.social_predecessor_sources(SOCIAL_SELECTION, SOCIAL_SOURCE)
        self.assertEqual(set(restored), set(runner.SOCIAL_PAYLOAD_PATHS))
        for row in SOCIAL_SELECTION['social_repair']['payload_changes']:
            relative = row['path']; old = restored[relative]; raw = (SOCIAL_SOURCE / relative).read_bytes()
            with self.subTest(path=relative):
                self.assertEqual(runner.hashlib.sha256(raw).hexdigest(), row['after_sha256'])
                self.assertEqual(runner.blob_id(raw), row['after_blob'])
                if relative in runner.SOCIAL_ADDITIONS:
                    self.assertIsNone(old)
                    self.assertIsNone(row['before_sha256'])
                    self.assertIsNone(row['before_blob'])
                    self.assertFalse((DESCRIPTION_SOURCE / relative).exists())
                    continue
                self.assertEqual(runner.hashlib.sha256(old).hexdigest(), row['before_sha256'])
                self.assertEqual(runner.blob_id(old), runner.SOCIAL_BEFORE_BLOBS[relative])
                self.assertEqual(old, (DESCRIPTION_SOURCE / relative).read_bytes())
                self.assertNotEqual(raw, old)

    def test_selection_missing_unknown_reordered_and_historical_layers_fail(self):
        for mode in ('missing', 'unknown', 'key-order', 'old7b', 'oldf04', 'oldv5', 'base', 'tree', 'path', 'duplicate'):
            changed = copy.deepcopy(SOCIAL_SELECTION)
            if mode == 'missing': changed.pop('social_repair')
            elif mode == 'unknown': changed['unknown_social_control'] = True
            elif mode == 'key-order': changed = dict(reversed(list(changed.items())))
            elif mode == 'old7b': changed = copy.deepcopy(DESCRIPTION_SELECTION)
            elif mode == 'oldf04': changed = copy.deepcopy(CURRENT_SELECTION)
            elif mode == 'oldv5': changed = copy.deepcopy(SELECTION)
            elif mode == 'base': changed['social_repair']['base_commit'] = runner.PORTABLE_BASE_COMMIT
            elif mode == 'tree': changed['social_repair']['base_tree'] = '0' * 40
            elif mode == 'path': changed['social_repair']['allowed_changes'].append('M\tApp/Unexpected.swift')
            else: changed['social_repair']['payload_changes'].append(copy.deepcopy(changed['social_repair']['payload_changes'][0]))
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                runner.social_predecessor_selection(changed)

    def test_each_of_fifteen_current_files_rejects_missing_old_and_same_stat_bytes(self):
        root = self.fixture_root()
        restored = runner.social_predecessor_sources(SOCIAL_SELECTION, root)
        for relative in runner.SOCIAL_PATHS:
            target = root / relative; raw = target.read_bytes(); stamp = target.stat()
            with self.subTest(path=relative, mode='same-stat'):
                target.write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
                os.utime(target, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
                self.assertEqual((target.stat().st_size, target.stat().st_mtime_ns), (stamp.st_size, stamp.st_mtime_ns))
                with self.assertRaises(ValueError): runner.social_predecessor_sources(SOCIAL_SELECTION, root)
            with self.subTest(path=relative, mode='missing'):
                target.unlink()
                with self.assertRaises(ValueError): runner.social_predecessor_sources(SOCIAL_SELECTION, root)
            with self.subTest(path=relative, mode='historical'):
                old = restored.get(relative)
                if relative == 'tools/targeted_native_selection.json':
                    old = (DESCRIPTION_SOURCE / relative).read_bytes()
                elif relative == 'tools/tests/test_targeted_native.py': old = social_42_test_source()
                if old is None: old = raw + b'\n# Synthetic stale runner\n'
                target.write_bytes(old)
                with self.assertRaises(ValueError): runner.social_predecessor_sources(SOCIAL_SELECTION, root)
            target.write_bytes(raw)
        self.assertEqual(len(runner.social_predecessor_sources(SOCIAL_SELECTION, root)), 12)

    def test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected(self):
        root = self.fixture_root()
        for relative in runner.SOCIAL_PATHS:
            target = root / relative; raw = target.read_bytes()
            for inside in (True, False):
                destination = root / '.same-bytes' if inside else SOCIAL_SOURCE / relative
                if inside: destination.write_bytes(raw)
                target.unlink(); target.symlink_to(destination)
                with self.subTest(path=relative, inside=inside), self.assertRaises(ValueError):
                    runner.social_predecessor_sources(SOCIAL_SELECTION, root)
                target.unlink(); target.write_bytes(raw)
                if inside: destination.unlink()
        for inside in (True, False):
            root = self.fixture_root(); original = root / 'tools'
            if inside:
                destination = root / '.tools-alias'
                original.rename(destination)
            else:
                temporary = tempfile.TemporaryDirectory(prefix='social-outside-link-')
                self.addCleanup(temporary.cleanup)
                destination = Path(temporary.name) / 'tools'
                original.rename(destination)
            original.symlink_to(destination, target_is_directory=True)
            with self.subTest(ancestor=True, inside=inside), self.assertRaises(ValueError):
                runner.social_predecessor_sources(SOCIAL_SELECTION, root)

    def test_each_payload_rejects_coherently_repinned_off_hunk_postimage(self):
        for relative in runner.SOCIAL_PAYLOAD_PATHS:
            root = self.fixture_root()
            changed = copy.deepcopy(SOCIAL_SELECTION)
            row = next(row for row in changed['social_repair']['payload_changes'] if row['path'] == relative)
            raw = (root / relative).read_bytes() + b'\n'
            (root / relative).write_bytes(raw)
            row['after_sha256'] = runner.hashlib.sha256(raw).hexdigest(); row['after_blob'] = runner.blob_id(raw)
            for deep in (False, True):
                with self.subTest(path=relative, independent_rows_pin_replaced=deep), self.assertRaises(ValueError):
                    self.repinned(changed, root, runner.social_predecessor_sources, deep=deep)

    def test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent(self):
        for mode in ('before-sha', 'before-blob', 'after-sha', 'after-blob', 'hunks', 'old7b', 'drop', 'reorder', 'add'):
            root = self.fixture_root(); changed = copy.deepcopy(SOCIAL_SELECTION)
            rows = changed['social_repair']['payload_changes']; row = rows[0]
            if mode == 'before-sha': row['before_sha256'] = '0' * 64
            elif mode == 'before-blob': row['before_blob'] = '0' * 40
            elif mode == 'after-sha': row['after_sha256'] = '0' * 64
            elif mode == 'after-blob': row['after_blob'] = '0' * 40
            elif mode == 'hunks': row['hunks'] = []
            elif mode == 'old7b': (root / row['path']).write_bytes((DESCRIPTION_SOURCE / row['path']).read_bytes())
            elif mode == 'drop': rows.pop()
            elif mode == 'reorder': rows.reverse()
            else:
                duplicate = copy.deepcopy(row); duplicate['path'] = 'App/Unexpected.swift'; rows.append(duplicate)
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.repinned(changed, root, runner.social_predecessor_sources, deep=True)

    def tree_records(self, root, before):
        blobs = {p: b for p, b in runner.SOCIAL_BEFORE_BLOBS.items() if b is not None} if before else {
            p: runner.blob_id((root / p).read_bytes()) for p in runner.SOCIAL_PATHS}
        return ['100644 blob ' + blob + '\t' + path for path, blob in blobs.items()]

    def test_every_before_and_current_tree_requires_all_fifteen_exact_modes_blobs_and_types(self):
        for before in (True, False):
            rows = self.tree_records(SOCIAL_SOURCE, before)
            with mock.patch.object(runner, 'checked', return_value='\0'.join(rows) + '\0'):
                self.assertEqual(len(runner.verify_social_tree(SOCIAL_SOURCE, 'synthetic', before=before)), len(rows))
            for index in range(len(rows)):
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
                        runner.verify_social_tree(SOCIAL_SOURCE, 'synthetic', before=before)

    def transport(self, command, root):
        """Explicit mocked Git transport; no fabricated real published checkout."""
        if command[1:3] == ['rev-parse', runner.SOCIAL_BASE_COMMIT + '^{tree}']: return runner.SOCIAL_BASE_TREE
        if command[1:3] == ['cat-file', '-p']:
            if command[3] == 'a' * 40:
                return 'tree ' + 'b' * 40 + '\nparent ' + runner.SOCIAL_BASE_COMMIT + '\n\nSynthetic new15 metadata'
            if command[3] == runner.SOCIAL_BASE_COMMIT:
                return 'tree ' + runner.SOCIAL_BASE_TREE + '\nparent ' + runner.DESCRIPTION_BASE_COMMIT + '\n\nPublished 7b metadata mock'
        if command[1] == 'diff' and command[3] == runner.SOCIAL_BASE_COMMIT:
            return '\n'.join(runner.SOCIAL_LAYER['allowed_changes'])
        if command[1] == 'ls-tree':
            if tuple(command[5:]) == runner.SOCIAL_PATHS:
                return '\0'.join(self.tree_records(root, command[3] == runner.SOCIAL_BASE_COMMIT)) + '\0'
            if tuple(command[5:]) == runner.DESCRIPTION_PATHS and command[3] == runner.SOCIAL_BASE_COMMIT:
                return '\0'.join('100644 blob ' + blob + '\t' + path
                                 for path, blob in runner.SOCIAL_DESCRIPTION_BEFORE_BLOBS.items()) + '\0'
        return DescriptionRepairBoundary().transport(command, DESCRIPTION_SOURCE)

    def test_new15_scope_authenticates_old11_old4_native14_and_all_older_domains(self):
        calls = []
        def transport(command, root):
            calls.append(command)
            return self.transport(command, root)
        with mock.patch.object(runner, 'checked', side_effect=transport), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}):
            identity = runner.verify_social_scope(SOCIAL_SOURCE, SOCIAL_SELECTION)
        self.assertEqual(identity['source_sha'], 'a' * 40)
        self.assertEqual(identity['source_tree'], 'b' * 40)
        self.assertEqual(identity['social_base_commit'], runner.SOCIAL_BASE_COMMIT)
        self.assertEqual(identity['portable_base_commit'], runner.PORTABLE_BASE_COMMIT)
        self.assertEqual(identity['native_base_commit'], runner.NATIVE_BASE_COMMIT)
        self.assertEqual({command[3] for command in calls if command[1] == 'diff'},
                         {runner.SOCIAL_BASE_COMMIT, runner.DESCRIPTION_BASE_COMMIT, runner.PORTABLE_BASE_COMMIT, runner.NATIVE_BASE_COMMIT,
                          runner.BASE_COMMIT, runner.CREATOR_COMMIT, runner.HISTORICAL_BASE_COMMIT})

    def test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout(self):
        modes = ('parent', 'extra-parent', 'missing-parent', 'base-tree', 'base-parent', 'base-extra-parent',
                 'missing-path', 'extra-path', 'duplicate-path', 'status', 'old11', 'old4', 'old14', 'old15',
                 'history34', 'history19', 'dirty', 'sha', 'tree-mode')
        for mode in modes:
            def changed(command, root):
                value = self.transport(command, root)
                if command[1:4] == ['cat-file', '-p', 'a' * 40]:
                    if mode == 'parent': return value.replace(runner.SOCIAL_BASE_COMMIT, runner.PORTABLE_BASE_COMMIT)
                    if mode == 'extra-parent': return value.replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n')
                    if mode == 'missing-parent': return '\n'.join(line for line in value.splitlines() if not line.startswith('parent '))
                if command[1:4] == ['cat-file', '-p', runner.SOCIAL_BASE_COMMIT]:
                    if mode == 'base-parent': return value.replace(runner.DESCRIPTION_BASE_COMMIT, runner.PORTABLE_BASE_COMMIT)
                    if mode == 'base-extra-parent': return value.replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n')
                if command[1:3] == ['rev-parse', runner.SOCIAL_BASE_COMMIT + '^{tree}'] and mode == 'base-tree': return '0' * 40
                if command[1:3] == ['rev-parse', 'HEAD'] and mode == 'sha': return 'f' * 40
                if command[1] == 'diff':
                    if command[3] == runner.SOCIAL_BASE_COMMIT:
                        if mode == 'missing-path': return '\n'.join(value.splitlines()[:-1])
                        if mode == 'extra-path': return value + '\nM\tApp/Unexpected.swift'
                        if mode == 'duplicate-path': return value + '\n' + value.splitlines()[0]
                        if mode == 'status': return value.replace('M\t', 'A\t', 1)
                    if (mode, command[3]) in [('old11', runner.DESCRIPTION_BASE_COMMIT), ('old4', runner.PORTABLE_BASE_COMMIT), ('old14', runner.NATIVE_BASE_COMMIT),
                                             ('old15', runner.BASE_COMMIT), ('history34', runner.CREATOR_COMMIT),
                                             ('history19', runner.HISTORICAL_BASE_COMMIT)]: return ''
                if command[1] == 'status' and mode == 'dirty': return ' M App/Unexpected.swift'
                if command[1] == 'ls-tree' and tuple(command[5:]) == runner.SOCIAL_PATHS and mode == 'tree-mode':
                    return value.replace('100644', '100755', 1)
                return value
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=changed), \
                 mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), self.assertRaises(ValueError):
                runner.verify_social_scope(SOCIAL_SOURCE, SOCIAL_SELECTION)

    def test_social_receipt_requires_new_identity_and_still_requires_all65_actual_results(self):
        receipt, expected = ReceiptIdentity().receipt()
        receipt.update(native_base_commit=runner.NATIVE_BASE_COMMIT, native_base_tree=runner.NATIVE_BASE_TREE,
                       native_selection=runner.NATIVE_NAME, portable_base_commit=runner.PORTABLE_BASE_COMMIT,
                       portable_base_tree=runner.PORTABLE_BASE_TREE, portable_selection=runner.PORTABLE_LAYER['name'],
                       description_base_commit=runner.DESCRIPTION_BASE_COMMIT, description_base_tree=runner.DESCRIPTION_BASE_TREE,
                       description_selection=runner.DESCRIPTION_LAYER['name'])
        with self.assertRaises(ValueError): runner.validate_social_pass_receipt(receipt, expected, SOCIAL_SELECTION)
        receipt.update(social_base_commit=runner.SOCIAL_BASE_COMMIT, social_base_tree=runner.SOCIAL_BASE_TREE,
                       social_selection=runner.SOCIAL_LAYER['name'])
        runner.validate_social_pass_receipt(receipt, expected, SOCIAL_SELECTION)
        for field in ('social_base_commit', 'social_base_tree', 'social_selection',
                      'description_base_commit', 'portable_base_commit', 'native_base_commit'):
            bad = copy.deepcopy(receipt); bad[field] = 'wrong'
            with self.subTest(field=field), self.assertRaises(ValueError):
                runner.validate_social_pass_receipt(bad, expected, SOCIAL_SELECTION)
        for group in receipt['groups']:
            bad = copy.deepcopy(receipt); bad['groups'][group]['actual'].pop()
            with self.subTest(group=group), self.assertRaises(ValueError):
                runner.validate_social_pass_receipt(bad, expected, SOCIAL_SELECTION)


    def test_actor_leaf_is_only_initializer_annotation_and_equatable_identity_bytes_are_unchanged(self):
        path = 'App/SocialGuideTemplateSection.swift'
        current = (SOCIAL_SOURCE / path).read_bytes()
        old = runner.social_predecessor_sources(SOCIAL_SELECTION, SOCIAL_SOURCE)[path]
        before = b'        init(_ reader: any DiscoveryReading) {\n'
        after = b'        @MainActor init(_ reader: any DiscoveryReading) {\n'
        self.assertEqual(runner.hashlib.sha256(old).hexdigest(), 'f79b53c8f0ab4ecdd4a21c2d23fe6a1c7b1040c50680dd6b6c1093cdcb3f2c5b')
        self.assertEqual(runner.hashlib.sha256(current).hexdigest(), '0e14cc76c72416cf152f8edbd02383251b2671952f958a18af078e883f4ffc51')
        self.assertEqual(old.count(before), 1)
        self.assertEqual(current, old.replace(before, after, 1))
        self.assertIn(b'    struct ReaderKey: Equatable {\n', current)
        self.assertEqual(current.count(b'ReaderKey(reader)'), 9)
        self.assertEqual(current.count(b'return .init(reader: .init(reader), active: scenePhase == .active)'), 1)

    def test_merchant_single_test_leaf_matches_reviewed_complete_after_and_exact42_before(self):
        path = 'Tests/ContractChecks/test_merchant_aftercare_progress.py'
        current = (SOCIAL_SOURCE / path).read_bytes()
        old = runner.social_predecessor_sources(SOCIAL_SELECTION, SOCIAL_SOURCE)[path]
        self.assertEqual(runner.hashlib.sha256(old).hexdigest(), '0114dd99ee717e599aaa60afec8c723b90a78cabe67695004ffcf957285c5798')
        self.assertEqual(runner.hashlib.sha256(current).hexdigest(), '62db96dacc91b709ca3c36dc8adb833a9a07826c89f7154a1e40f5d2949c0b00')
        self.assertEqual(current.count(b'def test_'), 6)

    def test_historical_inputs_copy_bytes_without_aliasing_any_current_checkout_file(self):
        compared = 0
        for historical in DESCRIPTION_SOURCE.rglob('*'):
            if not historical.is_file(): continue
            relative = historical.relative_to(DESCRIPTION_SOURCE)
            current = SOCIAL_SOURCE / relative
            self.assertTrue(current.is_file(), str(relative))
            self.assertFalse(current.is_symlink(), str(relative))
            self.assertEqual(current.stat().st_nlink, 1, str(relative))
            self.assertNotEqual((current.stat().st_dev, current.stat().st_ino),
                                (historical.stat().st_dev, historical.stat().st_ino), str(relative))
            compared += 1
        self.assertGreater(compared, 650)

    def test_new_performance_control_cannot_claim_any_historical_predecessor(self):
        path = 'tools/tests/test_run109_history_batch.py'
        self.assertEqual(runner.SOCIAL_STATUSES[path], 'A')
        self.assertIsNone(runner.SOCIAL_BEFORE_BLOBS[path])
        self.assertIsNone(runner.social_predecessor_sources(SOCIAL_SELECTION, SOCIAL_SOURCE)[path])
        for mode in ('status', 'before-hash', 'before-blob', 'hunks', 'after-hash'):
            root = self.fixture_root(); changed = copy.deepcopy(SOCIAL_SELECTION)
            row = next(r for r in changed['social_repair']['payload_changes'] if r['path'] == path)
            if mode == 'status': row['status'] = 'M'
            elif mode == 'before-hash': row['before_sha256'] = runner.hashlib.sha256(b'').hexdigest()
            elif mode == 'before-blob': row['before_blob'] = runner.blob_id(b'')
            elif mode == 'hunks': row['hunks'] = [{'before': '', 'after': (root / path).read_text()}]
            else:
                raw = (root / path).read_bytes() + b'\n'
                (root / path).write_bytes(raw)
                row['after_sha256'] = runner.hashlib.sha256(raw).hexdigest()
                row['after_blob'] = runner.blob_id(raw)
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.repinned(changed, root, runner.social_predecessor_sources, deep=True)
        rows = self.tree_records(SOCIAL_SOURCE, True)
        rows.append('100644 blob ' + runner.blob_id(b'') + '\t' + path)
        with mock.patch.object(runner, 'checked', return_value='\0'.join(rows) + '\0'), self.assertRaises(ValueError):
            runner.verify_social_tree(SOCIAL_SOURCE, runner.SOCIAL_BASE_COMMIT, before=True)


class FixedPublicDescriptionRead(unittest.TestCase):
    """Mocked public-read boundaries only; these tests perform no network fetch."""
    def headers(self):
        return 'tree ' + runner.DESCRIPTION_BASE_TREE + '\nparent ' + runner.PORTABLE_BASE_COMMIT + '\n\nSynthetic 7b metadata'

    def present(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        if command == ['git', 'cat-file', '-p', runner.DESCRIPTION_BASE_COMMIT]: return self.headers()
        raise AssertionError(command)

    def missing(self, command, root):
        if command[1:3] == ['cat-file', '-e']: raise ValueError('Synthetic missing fixed 7b object')
        return self.present(command, root)

    def test_present_exact_7b_never_fetches_or_reads_network_configuration(self):
        with mock.patch.object(runner, 'checked', side_effect=self.present), mock.patch.object(runner, 'execute') as execute:
            runner.ensure_description_commit(SOCIAL_SOURCE)
        execute.assert_not_called()

    def test_missing_7b_uses_one_exact_bounded_noninteractive_public_read_without_credentials(self):
        environment = {'GITHUB_TOKEN': 'synthetic-not-a-secret', 'GH_TOKEN': 'synthetic-not-a-secret',
                       'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'http.extraHeader',
                       'GIT_CONFIG_VALUE_0': 'synthetic-not-a-secret', 'GIT_SSH_COMMAND': 'unexpected',
                       'HTTP_PROXY': 'http://example.invalid', 'HTTPS_PROXY': 'http://example.invalid'}
        with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', side_effect=self.missing), \
             mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute:
            runner.ensure_description_commit(SOCIAL_SOURCE)
        self.assertEqual(execute.call_count, 2)
        config, fetch = execute.call_args_list
        self.assertEqual(config.args[0], ['git', 'config', '--local', '--includes', '--name-only', '--list'])
        self.assertEqual(config.args[2], 10)
        self.assertEqual(fetch.args[0], ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                                       '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                                       '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                                       'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                                       'https://github.com/liboyang42-cpu/chengyin-ios.git',
                                       '7b882973b47dee412b9f0a95e9ad030798ab2ea5'])
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

    def test_7b_credential_redirect_include_and_auth_configuration_fail_before_fetch(self):
        keys = ('credential.helper', 'credential.https://github.com.username', 'http.extraheader',
                'http.https://github.com/.extraheader', 'http.proxy', 'url.ssh://example.invalid.insteadof',
                'include.path', 'includeif.gitdir:work.path', 'core.askpass', 'extensions.worktreeconfig')
        for key in keys:
            with self.subTest(key=key), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', return_value=(0, (key + '\n').encode())) as execute, self.assertRaises(ValueError):
                runner.ensure_description_commit(SOCIAL_SOURCE)
            self.assertEqual(execute.call_count, 1)

    def test_7b_unreadable_config_offline_and_timeout_fail_closed_without_retry(self):
        for mode in ('config', 'offline', 'timeout'):
            outputs = [(1, b'')] if mode == 'config' else [(0, b'core.bare\n'), (124 if mode == 'timeout' else 1, b'')]
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', side_effect=outputs) as execute, self.assertRaises(ValueError):
                runner.ensure_description_commit(SOCIAL_SOURCE)
            self.assertEqual(execute.call_count, 1 if mode == 'config' else 2)

    def test_existing_or_fetched_7b_wrong_tree_parent_merge_or_missing_headers_fail(self):
        bad_headers = (self.headers().replace(runner.DESCRIPTION_BASE_TREE, '0' * 40),
                       self.headers().replace(runner.PORTABLE_BASE_COMMIT, runner.BASE_COMMIT),
                       self.headers().replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n'),
                       self.headers().replace('tree ' + runner.DESCRIPTION_BASE_TREE + '\n', ''),
                       self.headers().replace('parent ' + runner.PORTABLE_BASE_COMMIT + '\n', ''),
                       self.headers().replace('\nparent ', '\ntree ' + runner.DESCRIPTION_BASE_TREE + '\nparent ', 1))
        for existing in (True, False):
            for bad in bad_headers:
                def read(command, root):
                    if command[1:3] == ['cat-file', '-e']:
                        if existing: return ''
                        raise ValueError('Synthetic missing 7b')
                    return bad
                with self.subTest(existing=existing, headers=bad), mock.patch.object(runner, 'checked', side_effect=read), \
                     mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute, self.assertRaises(ValueError):
                    runner.ensure_description_commit(SOCIAL_SOURCE)
                self.assertEqual(execute.call_count, 0 if existing else 2)

    def test_fixed_7b_public_object_identity_cannot_be_generalized(self):
        for key in ('DESCRIPTION_BASE_COMMIT', 'DESCRIPTION_BASE_TREE'):
            with self.subTest(key=key), mock.patch.object(runner, key, '0' * 40), \
                 mock.patch.object(runner, 'checked') as read, mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_description_commit(SOCIAL_SOURCE)
            read.assert_not_called(); execute.assert_not_called()



if __name__ == '__main__':
    unittest.main()
