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

# CREATOR_FIXTURE_BOOTSTRAP_BEGIN
# Test-only physical parent domain. Runtime admission never executes old code.
FIXTURE_RUNNER = runner
FIXTURE_SOURCE = Path(os.environ.get('TARGETED_NATIVE_SOURCE_ROOT', str(TOOLS.parent)))
FIXTURE_SELECTION = runner.read_json(TOOLS / 'targeted_native_selection.json')

def fixture_published_test_inputs(selection, current):
    FIXTURE_RUNNER.validate_fixture_selection(selection, current)
    restored = FIXTURE_RUNNER.fixture_predecessor_sources(selection, current)
    contract = FIXTURE_RUNNER.read_json(current / 'tools/run138_editor_readiness_contract.json')
    paths = set(FIXTURE_RUNNER.BOUND_SOURCES) | set(FIXTURE_RUNNER.CREATOR_PATHS) | set(FIXTURE_RUNNER.REPAIR_PATHS)
    for values in (FIXTURE_RUNNER.STATIC_REPAIR_PATHS, FIXTURE_RUNNER.PATHS, FIXTURE_RUNNER.NATIVE_PATHS,
                   FIXTURE_RUNNER.PORTABLE_PATHS, FIXTURE_RUNNER.DESCRIPTION_PATHS, FIXTURE_RUNNER.SOCIAL_PATHS,
                   FIXTURE_RUNNER.PATHFIX_PATHS, FIXTURE_RUNNER.MERCHANT_PATHS, FIXTURE_RUNNER.BYTEPERF_PATHS):
        paths.update(values)
    paths.update(contract['feature_batch_sources'])
    paths.update(contract['feature_batch_support_sha256'])
    paths.add('tools/run138_current_source_projection.py')
    temporary = tempfile.TemporaryDirectory(prefix='targeted-published3cbc-inputs-')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name).resolve(strict=True)
    for relative in sorted(paths):
        source = current / relative
        parts = Path(relative).parts
        if (any((current / Path(*parts[:i])).is_symlink() for i in range(1, len(parts) + 1))
                or not source.is_file() or source.stat().st_nlink != 1
                or not source.resolve(strict=True).is_relative_to(current.resolve(strict=True))):
            raise ValueError('Missing or linked published3cbc fixture input: ' + relative)
        raw = source.read_bytes()
        if relative in restored: raw = restored[relative]
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
    FIXTURE_RUNNER.fixture_current_inputs(selection, current)
    return root

FIXTURE_PARENT_SOURCE = fixture_published_test_inputs(FIXTURE_SELECTION, FIXTURE_SOURCE)
TOOLS = FIXTURE_PARENT_SOURCE / 'tools'
spec = importlib.util.spec_from_file_location('published3cbc_native_runner', TOOLS / 'run_targeted_native.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
# CREATOR_FIXTURE_BOOTSTRAP_END
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


PATHFIX_BB5_TEST_SHA256 = 'efdff0044937babaf68cceca0059baf432c82a3b7fbc12d074b87488ab4c60dc'
PATHFIX_BB5_TEST_BLOB = 'aa274e3416b74b6c359c8bf23370ca6dc9ac57df'
PATHFIX_BB5_TEST_PACKED = (
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
    b';~z`3^wUpu^LKJn5d3g-@lOzaOQc^u{I9CN|G>1L44kI#zh>u;!+qQP|0sL+eq*_>Z}|V~RV+6;i=X3`2p1~*Huj;oo(pY>5-Le}'
    b'?N3;%V;$%IKL0pACu)p2$M!qMoNLZ7@V+ajpk{g(!7q$0TAwKM?`-$?=J911FUqeF@w2{`Ue)#6m!A>oUnua;SUlzbu1f-Z`_xK6'
    b'I-s-;Qq<|q^3_<-bmd>Ea=CxDAil}<jecIukeA~A#I%)t5c8zZ=Eo)wp6S*<8UF$8{^B=ZkRa@TY=Rj)p_u4=*55Du@hhTwSDydC'
    b'=k@Z_9RteyC;0y?Y5&kJ_|ouO!P3v69E8_EKS%Up`GkYgyM(X3BlLH?bZ|snds+Sq={-^2%gH_yZV)hK^R4=~2?RLh@Jt}e-_j0E'
    b'{Y!EO!PCuWE&Ftez;$i&mpCTob3YyTFR2>BUQ=J>-+t>pi;9=Wz5>DWSt|S?!~FI9UxDRoU@x2d1bIKhW9VC7ruk)&e@XTCjgg;$'
    b'<*P&TF0;hbD@=Y<<##3jEsM{p_fyrO#y&0XJ=$Lq+&iE>b@_Va@1^qe)-dF}Lib-oz2BSR-%<{Z+j7Lu?%~VEpRmDtS-_VrzH<#3'
    b'zGO1^vev<C^0kvDua)oStZ3_v{T9cke8kr?VgJl}%i*(W{5I`>pd1Ro3}oOaUxb5?&q04G+zPDI4n+61s<;2W>%kD4{SAv>$NC4*'
    b'_p>DW%Bg|T2c?Mcs*Sb%!Lk2QJWsuTviWy5`b&2G>~{VWlh@>5FZ?>Ae_JN}vxvT8?Kd+I^Z2ucDk}O*ErRte_MASGU`x9Mq@O&b'
    b'&y+G!1o^ANe~#zNj!f|dQQkckRS7h!yih=3Er*xPf@1htr2SfM{S%L{SbI}{BDYt);BGWKaJW~;=&R%L>?Z`Z&*?MczT&j>>XH5v'
    b'mq3dz=lyCF1;c)}mjzi6^{;aH)n5n#gJ~&pm^@C3{mvPGNBxzrKjHCPFyWfcQ^}ud3V!?v1;5Ph*Yf}Gm`Kl97~t+_E>+$=mq7HA'
    b'?#Q3ZV9u)?_+IJ0RdssV`D<MNsPMN$Kl?2|q2O8xP)(5HukUi;<p$6Bs!v*<%~<;-rk?OrO+6#1pNZW2wdyP&KNI0EOJ;wvYVcRI'
    b'g1Q3EK4Vr;6@1!0lKuKWxcJV}pZs1`#vhXOUr~O-MMZy=W`~Vuy@FNPqJOID$wCQNvc3{}K<9fj_{(vd%X2O?_^+Pz_ptTlp1R<@'
    b'7na^j6n`&{FjTz?iLd<jPXFHl#qZJkSI7&J`r&V-@<yv)K=_>|e!sB!Zv8#G#>yvFcxvI*d3qLPVGHhW<s+Q6_1ki#ldcB;e1^2&'
    b'hvKgVmAAwGtboJCn!n-@_{-PRPggZh&tU!?A{)XX6rrjFKYq(vZ#eY#6L`g?pIy4ID(6#nFGG3j_OrY2i<y1`lz(LNRn)v%kDtgV'
    b'%qG@X-TFPBJYDO#q$hkK;J;M$yCw69)88t7N3w4P?Pu(Il@m|X_$H&*<o@1Re?>g6aeu*{z~H~Ubg7<9Bbd;u74sg?Ygy~rYW!Uk'
    b'd*iCV%326gM1IX#|M2?PEMG5vrlV(bJRI07=6y!Wugvsk(e?L)KS%P;k>TRn3s(FL?Y{=_lcEMA_}gUkr(AxG%YTxK3?(rAUslvN'
    b'0flEz@vF%`2n791j*YP8@~a}hIZ_zezasf(Geb1xXD?ndPwzU{G+r&bKlVl5OCv#gR^E-sf5ZQCK|G!PzMS!MQ^>36e_`IYzx}}j'
    b'{)zt2&cWNkzE|mQt-bnhFQGnDZy*L+`^;jN9e9KNuVxX{?%wj3D(NRG|2f5X82nsT)_>-SXXpAeDE=F6LE?PV3M<?oj|NFJ$euyk'
    b'e0$mV{?7|K>hJ9HPqYu8zyC4%J==hxDgH6;{fu|ttoj{3{^--M2>N&4{QDQbjP3QJ_J)?9UGGoV{c9BYds@$h=Qo|N*?a=W?<>Ba'
    b'4)zU8{`TvBC$>Ks)tgI}tY&iPN9E%;QOLn*F_RN=vWQ5zoRmk9d^(@cW%Ht(E#`A_1}+w}c_EWatC^yZk(HdB&B(BjE@og@`0c;`'
    b'>%U}0{Rm?JYtjGd33>5tRBw*}q5pnu&iX(9=l?X6=MIyPXGr_7H_FE=QvB!Rmp0JH)1IF*d{yHgU!MMv7eAgvKb|h|BcS!7sTohr'
    b'e>}@$H2eLVtFDQ!&nLkRruqE%;~5N$r!Fn<{lX8ikdt3S0vk=XKB5L=s^44YYs+zy9WMvfI@4@G(3`IM0iK*^f9=N;5IpGx&?OKe'
    b'7;u1oY?O<v1*pIVp^r%A<Il*wW&R@e^`CkA_@w!&!Zi6s?5_yaI{n(GEZ;NJEahV==#J7noy-&XTm6k*f05bG^!V|!fBo@U1HY&C'
    b'UNU`3>Qk3r{_!-JucZV%NQTyHc%e3*&4iCvg&Dr_@kZ4jPZ0Lh>$5-z9N;62!`4S&rXSDP{P7u)tx%cIXcp*7u<Rd!9b3wi+mBEE'
    b'{N~tds_@&VGM?eu3LbqvU<Gm9etiKxm%RfsvMS?~qr9I~pMDlR>EAy;o<1bq3P$$g_TxE_pArpp97LZF&3f%X2%rlXJo}&5fa<zn'
    b'Sq(*n{`=#(A4uCfO8DB7=>BQf0oCAz-x2+D!q4ab^8r3dw}P_c={5oNH?OMY?WJ$uLVw2eMfNii1oM0H-3NI0Bl+>$kKclSpA25#'
    b'{C*(eORo{_KmL3-<X>_8_I~j0OS=F4Czjaw%C6sS>B~66iVgaOwyK>1_pW>x+8+F$*YKZO-JAa#%;taO&krwQ%TL~~Cw}JlXR-dj'
    b'za#h@-T!=X``>`H_}gzkwq`*8WiS8p=9v0`|NBKu`2+$1OX&A@_Z0(lWe>jSzP$7~sbD+-l>GMP^V6RT^>3ZG`_2_Vo%f$5_vyGV'
    b')}O8$c%!Cz%RhSXH`o30iNAOAuNnVE(0hLy;QObP-jo0O1pOf#{$&RGe~M;*B9Qm6Ki-|{zZA;%-1Lcdo((!M#BTrj_{20ngIo2v'
    b'pz`s82T!d$D~GR#VE8{Dul+k8!pCPG|M)7{pCR{iP|qEEKmO}Qum4PVuf+eK-=(*2<=@9=xAh$&!}Rz)n!kwsA&h?nN&n-sJ0Sn~'
    b'7zb~@)${SWNc1B1n!%I)ljM6MUkOuxtzN%C|MPV%h>up_UmwpZDKIxD;Qe$v;p1x^=xOwA&Hi|SwvVs9L_c2iny-ZL=KPf0w*>SO'
    b'`^R&U>EqS33cj#{S6{>X9Mad6PNr%9_|nB&uWySB*LuDyHB{uEsr1t--r{*CjW?n1?|(1CKg)=}q!b|Fe?jDr0}9{%`QvlT`Ew`E'
    b'57{ve78v~Y#zK3$lKIbvvbUalxdcnnw0A~(2KWDO|JzST`<;(|frww2yd3cJf$ylI)@=1h%@?R(|L3>owiN6CzFTk4Ugx`)5EA+E'
    b'9OiHT`*-fze46*m{KM&e>hhUrzU2SgPcgjET;*?p<KN8h`P~20)Pm>V|1N(w%O3~tU(W2C=e-91Re5>AFRB{UPoJ~<+A$o=?xo(B'
    b'SA$<7_!?0#a2P2p6<M=i8yf^!d-Wl{-u{&No8)T+@Z+6aK4)C(PkN2daLPg-x9`8zN6qTEKMEl1nEd^3qvoJWef{*4_z&ms^sBF@'
    b'*l~4C)tCS7;eYtK7m%7Z|B*<4G_KY<|M=W@P5;%SUo!lk-&93-ZHW|Li$Py~(*ON`dFOLu_B-?a`l=wy;IHcZU8nNrhVQ4Dy<dIq'
    b'GYe45>51E(|Np9J#$R7HzBV+1K|l#IK;^eDdrjrV)H`#fJ}CvmzG(K3ld^s;Rh+<(@{iALo1eii2&MtAK``WRk37L46r$qSZuh_&'
    b'p3usA?WhA^Q~ZWm0#6MPq3{{GUPS+I_}-sA_2XTR{xEj3b^_lY-r)Q{?*y<kci*u3m$QEx$(PUk3a7uba8J*_a(DrNpC0x_;u|1T'
    b'^zWoALFN0eLf*e){A<AdXP$o>i~c>!R}B2d%~F1S_cQ)h!sPlV>iVi}-_QPdHbFh(xj8jJZm+uLD<waFdRi*@E6Dy<%6@w`(1fX<'
    b'74Y4Qdh7VdYq{yoercQF=b--dSqS>?KXCbL$o#}6&lP|my?;X+f$u!M_>DUL`{P*@eX;*_3a0hrHQ~P*`+vUc;TN3wO4?6f2(TvG'
    b'uT#~|GMo8c@IRX@l8VA<NtHACVpc*?Ia@$wG%w{5Sr$a0h{#A*5_2kAD4@u*BatbH`CL|(lr&sGva0mk?@2#X+mo=07GXt&VO7ng'
    b'i&7pfq!n3AXOw&z74w3G<g*2#APK@B2)uh6PXO|DaaziF$o$PtGRXmwEGyAY^J1v?-4dXs{Za2*$?YbpqNsM*quu_sqj!l+UhRVt'
    b'+r8(GJAGR2l^&MSqQtyc(6&3Z%AF){ep#uJ<8EK(hyfiQ3{>cfW$KFDRXf#8Olw{j_nC2-sFa98VVaL8a%p3SAH1eqqslCXtc!wl'
    b'JM|q*&8#H+R+%&o^GB_pawjdqktXK`<PD^4#dDKfHUTt1ZjqJ3Lk~yb&W<hOg#&w_`?|iFkJ0lazLz%Fvm`@w&ljkHH*cip$@~H?'
    b'D%fPOm>m1cfjVW&^YL(fyxx+#t6v=A^Nn#V`Np*8fGahg)Y`*|<uQ7r6<%7YR-39nDIFXOAI2H&Mpl#QDXp59rCaM(e0lEVQ+6$5'
    b'TfPR(uBG#IdTRomx__gQoqvxTk*j;ijIPyI!&=_D<b1H+?>k8!<c?%v1%v!!5e@&yJaQCc*^S$ti&w9Z!ft3BU#m6q;&#^*yIbu?'
    b'Mc?jq2@4IBHY#>=6{|3z3dnxRT!HKPp7IjTaN^Ipg_3^jDfR5F-ZHPJGJyAZb1TgBja>@=cz&F?lIzr*fm@ZP!!^B`sitfi$aLM_'
    b'Jd&4?114Q&lvik8GxzM#iT7~qL`S%8(dSumNG?<;dfRO6h)9oTer=BO1K)2=N+xc_h)DJBbp}Rw$TDd%<uP=vg3N3N$L0cs<O<sj'
    b'+{RN`ERx{2i#g8cm*6$dp(b9)Ol7)kagWR`f6~0e9jj_aJfVq-z;n^0Isz@w=R~WLMH~KH0{HX3mfwU21DS^hCNJWxX1#D)H8-Z-'
    b'^cma7Gq_N@<f>$BZqf15(jkj!4`@>R<F$}Ch|JF0CiC|)kyNYG0oWJM8QO25Q$AworOBAkmYa$`X$QoPQgRg@;;>p{XjGbYLEMW#'
    b'Kmt~}^W6lrE@gqAjoL7;^%cgmHrsBYm{cJy)hx8{i=0VS(solws;jG!YDA%Ff7M)VV#7+zoYQs%OlCT<{AKSo*~<<OFIy^e_miwE'
    b'=~n;fyC-}w6O7UL0FGy*;NAL0W1DiZ1KwbhCuQoV5pG;C?Hho1XHbgoJ$5JN!eb2N(b4tYFO@9Xzh}K!bkepv(d@Aqp@?a+7#<F2'
    b'T|2`LHyW-oHR;R%)IC~TokWL^MBw@Z5F!LRt*%G>m`X$HBms^9Vw=x46{TFE*$aiwh5BT)jc%mv;J7`_%G1{JvX~PV(rVvN?OJX='
    b'ZHKloKjQ*jzs2azIZ28O@pjmij7H3Y;cDlRFY*qP#^wn+lYGR9Sxu-k2dM+wtq}uU$#<6ZZPRU-x7m4soY7{_xn2i3cuKN6@5=6_'
    b'=xjOeh|%z1pv6_+a_}$%<@V9y`bJgJRDZeWw<qoHB<ACzbA>CGSS=q13Et1wg^V|5M*SNzk<eq{yX9(PUl3!x5*90#uk(QcZ+)aO'
    b'>Fyq|%`a{f*Ex#eVOZmJ=Z@PPkZA9`LyO+fMT3MFnHILsALD7mOq|(TPTh77BiR)%qO*gF=Q&@i^)QUhWUK09Z2JD#V+kUPU^9Qj'
    b'-nC&WH%pt1#yWjO<Ew-h9#p;Vy71vJZA^<bL0I!KDgsSU<$EC;k@(?Yh)PDDj><AnEci-&lAmhz#IP7ww!^DB3L?pRI91!Xfls5?'
    b'Yw9-LSBi=(t;`H$5Zoa!@IiHx2oEnq88r=<@toH^i<q+CYg4Qmsp#4JzF%B&b^_WxCdI0yV+57Xm*NSdlPTcWBp;<RBVU60(ik~S'
    b'YuYI7+E{dg*0F<~8lsmapJ`~YbO2%pGnAq5pp!AS65YVrF+DeHJ#kh#Ny26VjL8|^_15W1W74W!5USTR%;{e9iD?RRSMx(OjaqB8'
    b'y<1*|r8?y_h+?c<I!OaqBF8OR(Dpsynmna5;lT<9xXLcvrpv8M$!esTTw7wYn~QDCW$sd1Db`Kpz-u+*H=^mh#q$GXOYIaSa-I_N'
    b'QY?>64$Z>4n=Z}^4TiOAt0u%J#Uotwt-R7of=8Ey+u=dg;9z^gh6SbBn2v;DbDQfnXG{s}T<R3OBaL+d>nd@wCzsIl?OuC8dY;S`'
    b'$g47I^ronn&|&73!MoE5qe2yNU%eP*V$2w;Ui?v1_Ikc#?Q`J;esq6+p$!I-En?uaP^Z(uu-pa63k3&TR5#gbF()L!t?KQNa^6i;'
    b'R*n*1Ugl}NXn~W9yrn(9+prhubUZUI0NB8r4V_3AREbFcVlyH(xaY%zS;0sfjkLu|qN;VI;d<ny@6ak!s#J5+OP{sXG}4+JI{Gcf'
    b'Y>6Nzz%zi_$#OMsr|1fGkt8pV!uz%=p6;69)WC7Jh8Rrw?ChB<v@DIvjFJoE{B`@du8>LuGgR<ATTvF`fs4dl6?MsP+6Kx3PGx=F'
    b'R5F)d8yUt)qB_nBp6Q=XQ%cvUUZ#*PaA?J=WnihIH2Q3;+|=ukkF2`W`<jY)m0WmWMBd+$*Vz>4?10A90!8C~@O-h#@g#QkOFJp+'
    b'HWYl2N<qw>uEIxl(Y{^+Qv&12c#xh@qS>c<B7PYr$%!B|V+U{<uT4)JensjcE#hFSNrbVt)fnBqY_rmZn2lZR4(SWBTHC3J$SUv('
    b't0mHOUu+BRED7%lrARBz6uVX9V6^BeQgG^xZj@TBOrOUxsq>|ExK7T+&EzT%{VN;m;Aniyn`C%M<!JgK0CwSZOF{)Mxk(Do-px|1'
    b'hI-p*ebwWH)qMqQW23;o33$_45kiDbv>VHvXL)kk+M;Dd401{7-0-ioodw2at(>Ql4i%Z+l82IejL*UYoiDu}7^fqHgH3Z<i>7CU'
    b'p19J)cC}-!JED=W{5~lowbGL9MaLBn1%O;TTI5Zep>HP^;kK(>rrz5E7ksfAiiLFx7&X`Y>{^ZwV(~6~fKTu-yr5;|)Nti+?xgLy'
    b'DV01_mRr5$eYr+sw}N`$Z*m8caFGVZjs$jzU6)SBK$=b7XVuR27C-sb>ji3N?8e^in#5%kEwcJ7YIMwFE*0s<Atf98iF;%2sfW>V'
    b'9KBqW5<uyC0a(@|dn>Zky!wb>y+dA1qN&Y%V3oQDI%5cnb`o0NmXmyIT*&gIo$cHbhLDFc6R>~RQ%a)c(vQ0n2Z6lLw6I>tYqh%p'
    b'qm<Wb=w6~I`Fn3(t8DqHZ%?jj$yZUW;GL5mh$pws@(k1wvkte&4Ry)c^Wv21h+{gx>9)Hl+O?$!^f*_}=P|)eFeL{AK@mtrIVHT1'
    b'K+6nb&9jNu;D`(H+0JnoMOTm9+%Dg47q&?<_sjs5V_lZMp*0jt_m+l?*YglE0ZIKap{B|9!=<x#I8AR3=|Ta3qqkZ<8{;i<vx1J-'
    b'u@?&u1}fok8TDOgnE@u=vI;agted>d#ga2oM4}su#mabNeOI)(vn+_^D-fjKYu$<6JL5DyLajxrCl+a_opxF*(}ZZ6rWS4`zlST6'
    b'{+{Vh($Sw6NR*kJx`h1GeU$*GtD(A>8a<_YyD!_$WhYgFtgp;6jdgOktZHQS;$gidJ$>MD_*5DvJIr*_xY$MMupM6}dYiNEsm5b*'
    b'+viG)rZc-pg&o>EgfWVZLH)o=o7Y}jKeG6-ALNs9IyLv}USCdciRmFmW+q#h-+7BW*@jp&vdWOhF1KZq<mDmWGmZ9avF?=B8PJTU'
    b'nS+|HB%JJB0>ta3<BM!(A0F1Tza*{|!(AkUJX2{D$`8fCyj8Yi3S6(<bmtTKl5oqLeSN;dP^aAh63Jz+e3wVyt*k;~ojq&w`9?eF'
    b'W+5H*(0z5DQ1#xuzwy<L7C{G_@+G_&9=}4`og$irepiy_rF5iK@9K~1P9-x$V8N5lXuPEpeQ_r6n~s$dE|s{^SXL7Fd`n*LqYBVo'
    b'EJ)%y-!ep1_s$B!I6Lz+szkCS#JvVJb|MXY@v5YvY$hJlGAkl5;(|4a^Y`c)?2asIuEvLz?(u^4*CLkn$a_*)7P>t{Fb3svyWJ1+'
    b'JJ`<6Vk4jmPG{5%s2_O{0S}kHF-~}mMLGz|ag|7h7X``EZF6dG`;-A92Wnfy2jnV8NxYFo^IeF`TDw*+Eyt3>w3v~`J!qZN<->?!'
    b'm&4t>-#t<qh~IV+>DUPkyj7Id{N74C?WA834J<Z77F`PMgom=hD_FX2sq?}XvV0|;Ib6<{Go|hNfvum1c1PHkbA2Y3nN&cKA;~*D'
    b'tS-{4LDx&CJ%5o0cx&ldK{=&u+D&2Qr--(;X^3aKUPP<%bh)?*;lalXOumq#aXOOF=17*h;)%PNb8(A=FP&+gAhljr^3e^TUJu0O'
    b'Y#?^5lcIa`Q@ys$3XvU1#CP|;fyhu^v?47!zMjY0tLO>3Yhb+Ywx#Kng2O|jHnuIFq-(sa@lmoDiL;!~YzK@zAGdXWTz~kaH=A`+'
    b'Y-Cem^QSs~T&b-?gNu8uVJSXEsP3)Ny1H6zlQb#>e+833Bo>sG2`161;N?{#+X^puj;*s;0(f*F&~vSGwsCLX%q0h8GXA>S_bGae'
    b'<s;+vT0c=y3MqoSo~^~}tERU@Rm+&JF~8{h4OY#T;1L%Cv&~$&ySV3p_GTma7C*$32xW)79=ZD1Wv|3K+0K&{9#}a@(SAf(g+J_r'
    b'G903oy?siBlgsP5u}pWULpB4c?W<HBf$*f9FiW`J2f%%tf?b1Ot<}h&u;W0NJ+AqNT=p?)|MP;DqMa_0c>-NTOiSeRGtCMTy&*|c'
    b'Aw%Y<UaOEFxj7%9(ZgO&pSt%Hvm6d^#yw(@%C46mfT{kuQa9IqeV9!5JdZm2df|w9)ktBcr$;==hle>jUDC|=cig^2DP_o0^nSn4'
    b'ST5Iz+8vm?2*C7jr!<vg#8Fb1StGYPybg2Ae*Rj7fbG4LSi)yC>F;uRNgCaiLa7qu9_7LwWBO&eKU-s}&xf_caD3P;9UjE1Ic{8$'
    b'UGya20b*z*TGDKU3UhO2wFfDI9hQf+hJYsb*NR4Z<+emOdsCricYLOvTxaL>V&kRl<+?H0>z#eH(P$W;O%9>Pt{nC^qLGLVE0vBk'
    b'>Mi>Tt~pFA+}1>5af+sua_`WNmsxbRObrt55H;e<=2*od_0~~p?e8>;ZPZm^?GeBjPE6KYc(zI5;GMI#_gH10sl_5)0tdoAz#*ZJ'
    b'8fI>tT<4G~B}xi`R#F5J7;IO*k9@YxGs*e=tU%LFFBM&B`|Z>$8tW20<MS7Xdw5BEBXfE?kJK5s&z5@op&keNFx(U&za~{Ei^_iS'
    b'Qgk^wY~px{9T0psA+s3<gnZgG#t#czG-AVZC7;Dzz`+$&(XYLs*AbWP>4>Q^mR%tWTt!IDq7q-8E?euJ<K_uvd}<U(;i}YQWD_~X'
    b'O5wq*d#I+krE6r=J=e~Me&oLD>hxfj#nRq&Zc!*oAIt6>1Po_!*)L4pCl96%+w~MaSg}q8Sutqfe~NK0rt~%BWLD9%c!Lv6%t#2p'
    b's(mdoOo-VW<<>lCLSx+C=1!LfxFdw4ej82(Yk*4*qqfaf1*2s|!QQla85pu|93HUL%YjBNeq8V!TZ=qaE@2`?2yMo(=&HRI`<c2y'
    b'vNl>m!HRy(J72sygm)(g?q$DeVv}r)iEpB0iAVbR>0}X;yz!lbRd{di%Pl*#8H?L>w1W4m+fLfq>(}ZcnOjYUu3C!jOD%iA4Zt?j'
    b'Bso_UQr&&uj~n{KJ%{=#nALq*?CL{m*DM`wq_Y`SMtyvw3~E{|N<my38mD{Epu6(BEH1<K_@v+Uz+}R$54X}{X~yW~VBZF6vsk>!'
    b'pECdy%Xwy;Bpq(N>K9w`G8*Ff2^q~5Y-)JIduXB7Zr9M#@Ko5+q*Kbd08TzQ`k2%oi!I5b?Y`0Kmt*-=XI?2d$dMIXFPE!29T4C4'
    b'(oH`JRqnP_4Z?-nc$8dVR~>nkLN2^WvXksDQ`d<h@$RCuUV^lSE{1oe6jiA6V7orh(|U_Z>QN4<@4CbsBDS2f70m<K88Z~#nVh{X'
    b'^O)6(+fm=cj?De2cXwT@VB8APL##m05&yOfYx7PY1Db8F-&6`(Ia%K5YSXbOWWLKWB_9QJVwdo&;yt6}FO)vfuu;}O>~G)z!YR0_'
    b'?01U?0huJ!xu5&4oZw7ijMTA1!#WX!qiu<@vkZH%y^4LVpP5B1XB766by)?wryen?bhwhqxkU_L)ZB?NEEIB3x;F3+dUG{RCq|Om'
    b'%=J?HzA0f?VDw6HE-vvyOEEFdZBOyt=8nWmT$~|K@mN^vjaSJ+Jie=D&Me#<xYDs#F1YjgWw}1pOjwp<s=k66tIU*r5cLE)Uym=C'
    b'0OZf80G`R(1=^+$B1X*9mQp@yc1yIQ^8(h40<hH3`CM)|A!^~ltaKu+rz8-_ijn9(cQ#;IYaIOrd_$KsWfrLvDqy2_Bm<%|smzmU'
    b'&J2pH(in|5VR5oEF?UKhiUV=fRjupx^O*I5UMtS`duT-F$Jtitd=3xNm18_xc7<p&C}5CYd3~MDZWXx&FHVVFl8r<b?xf|wO1_-|'
    b';ssWn+>9Wl<~BFf)!LB~fzr%&dj=6GcW4`}pe}5835VFV8u*aR3LO>QQuVN|tZs{&44Dn0aj|ia5_Okx>*i$78YOTtk67oTJ}je~'
    b'(rSQ|9?kjT@xXh&dT){G)Na19@@+lQLdMk<lOd)tMo!3cVje3=eu}#th82RzU>z+HUKs4TbR1}2@{1|5aw47au3njeLCurw#M&AC'
    b'a5)q`vjPvyjF$CRi*qR&d5{E9;QP!q5tSVw4zqT2&)VDklI%s3#caE`2f!1sLEy{m+Guu0A&$x!5V4~Ssl*5B$@bSmc~5KNI+{s?'
    b'3mQKRkK}lMFf)Kzwha@)d+W&tU)7aaJ2RPW2-sw=+&<Oc%ntVrr{M8yr9&QVx`laONuk{Gr0oFVg&zv;j_Lw0oC>+>4roI+Eb&O}'
    b'4St`<5W|-2k!?SHZrKYkX-LFkd9Z6FJ}fOrh93zfu{j=ez!X#>yvGGPf<8v_+IX{Dn!cMES3L@v9!vMIr#D#~n`FB1z&7y&Nr>3#'
    b'=%;Cv)*cCBq9B&cm-0m{+q`twV`Z3MDcfy5f)z0+KkJQ76`g~6eSaTGxGJ-5S1x&>v&ljA47x5Lyg!@wBeCc<?0qeeL}9zEi+Uaq'
    b'cNR5Gl_EgDBGi}J(t47iIwh+)pJlnlT$^acc(h7B=!m>IRiw$~R*d+in-D`c#YIJLkrADf8!@Ne%B{0B0k9^((h+iR55vpnEY4e('
    b'kqP8zhsZ9~jdqH1EK6%dzmporvs0$6b~@4AwgN|5xIMlXTLm|UMS(U8S?DqfC1T4M*KLW9o1R+Q>csZMUUxa=z|<0{NX0T2e}sMP'
    b'I8cmW+a_aXn)9A<BYK42!chj;ANxH;8akW9Uf2~MTYhEPb#yml`|&eh%pGehPmRF1yhxd=c6-G4D5Y~NL0<f^=@;h25`#A!lBPsv'
    b'vI`Gpt#td~c(I5Rvupac0~JZb&dHfs8qdy2v(Gk0vS2hAi_n_2t+^+G!iMq0__45nVF2xn3)Hb-!WlqK)uL1W?t0^Ci+@n}<0_wx'
    b'EE6RT=D6^(z?DPaq=T&<FF<WQLGX)R7gHK9qt+bN3I(Uo$$3?z?F;p+anVP7DsF>1lpHH`BOY5ZC#HHp+cI57s|m4HsuLot=0!LK'
    b'rXxTrT{CdDIt?$NRi~cf0;%pi1zv-qM#PlJw#wcsV^?nJ8+^Ik>mIx8E{yV`qaL@NY+t`La;q5^A(pkRKaa((<C>n4SejQZ+gJi@'
    b'jqxtQABjR)R2F+8pBKVhd7~B<F*_9=c0F=~6@*{kllhUhkR&u$w|04~+l((Uqef{cpoq|r9Ghgkn-k?Z3S?+i#ieE&YbX%GS&Qp&'
    b'v!9^laufg`aXU5OyiB!IXohQ}{Zc8POeL8c=ku3G{6tRM%RR&Pm}&m#FX^TpcaE}?5h{I|U+)&BY&m0soZYMvi`mM<<#>6G+<fL1'
    b'C8wo9bQ{|-r?QGe`JT|(nb|>CtaQWLp#+?gaV=4$6@mcovJ+G~gneH&#JoYqu({D)Mvh6Lkst7Sw}EYta&OqUCAG@BGf_+COc_8;'
    b'Y@IpX0G%OAs9H|y3Gs3rwDS%X$=^Ycdk`U>KT0d_Zj5`zd{W{|(|ww&SA`8_4&c+NIWJCWm8YU~;7Ykte^<%Oy@Fe~Pq$jSe4`h*'
    b'RiPsTtXb69sj+5u?(*K`4+B20#W53+r}gT3QOt!0a90LQ*VJqe6c&4&%lonUO2jI#n`Da`v2Lx?UUAYerb4;qYw70PO(82Q$`MUR'
    b'050_7aFxy;;;lRL`b6)rg<{f<4u~uUbcjZ&xS{Pq4ZVh!NR7wF;t)UKd;#UK7!i+M_V^Uh<5Bu3B<)L8(DWL+f>60W%X-anzk59N'
    b'@5hNM9B##RytEk>?c=yLgQn7MfiIf1As>&PK(2sC_iej^;E|ReUTQu!_T9{uGvd3+P&-n<a=6{Lz0P`W?<Q~}yCxGwHdaj+z;X0a'
    b'Tb_w70#v7#(@8YNOnNpd>8Co$+!{gIp$F--6v3tl;vuZs^|y{#s`PoF5Y`UaNTN3@(<D-z6?5~$KBju9bAHt~>3EiyK)zllFRAXf'
    b'H5B67l|dWXRI{&pL$}wcE>mm6Q#}q(w7k>|U@Zvdz0E+U8qr)+bc;w;Yw)Lx80rh*GV^tfmxXdeSB_N{K_9LMm9@oUn=F?4d?gF{'
    b'*~mEyR_P!Sk0SP}$w;>YON)tY<Zhn>uWR(@SShz*v_pD3h^H3aF+);^?XjCc&puy0g$Jgul-jwIwpQ&9LJgK@K%eE(r+rZ6V%JFT'
    b'G;+!^WN7Bvtf2MIYBZdiZiLE5?ei=d^CGJUUZmyTrl-VvwQ^rSJMn6=l<E}ozUmFnT{l8v1{EIMe-QEgv{Al5QcRYq#$W@Y7YRKZ'
    b'n#Z-byV`Jck)yuf&!?iZTG3h!OQos>45byI#4FAHX59eqxz>pnx7vUmO9t42Ck3>OT3$L5E!Mb3pBjZ1W2|D`?qDP#!^GyoIIZS&'
    b'oI%Ero|z|YNsY^hO$VTJPsTRtbv`(kLE?~2iRFo%lrvLF$aB=8nonDfyxCM(s$bph{ETw!WG9hZS!wo!0++;YVQ+b5k7}LOzO5_O'
    b'S#A!TlqJt~>volKMt!wV0s2Q_Qg7<pIxJOnCttrpi%xB03PTW^c<_3!)e|R-qH9f#6wSPC>Xy9o^>X!4yvL0}1bB49zNpZ8jL6Q='
    b'WcR(%bsAfVlX7IZUJM4*eSZgbMQEZ$bGt2HO#1oMF}?BGB(i4vqfzz_Q3!G|OqtXHad{Y&ScHb=4t~!GqdHohde`BCC^SmDutx-u'
    b'Lmw)!T5&l<vwkT(AT8;T_En;1i6%T!xG~+OO)e8@_Uv76zz;>!U0qg-?!AmR8rz5`v0U>=Bi_Rnm%y>s_i=n-Fn0MsBe1y1Y)<3w'
    b'(E05y&nE2+dM%%G0J53JPTge0XCyp1szwis(zs*}yC4g7Zxepruoo;p9WTn*WLaKcxV&D8H(Cw2WpaKen3HmyVww9;^<BH!=i$z!'
    b'o=uJ>;f41lN`Nc%qSq9-8$tGz>&iUpr7Vfk=S@l!7H!*1AhG4zK2Dnld(TfFNfc?GT?tj%GSnqbna*&sX3^S?iI%Oi(THd2Hor+}'
    b'MQ1Ll(drDFg}IWcowhf@?U6+Pyy)CP%(SQGDiEkNmcdCYbE&j35ns;F(VBx?lwqP|dOo&EsmI6tI-7u$CPf<EK69~aIaGD?1BI#2'
    b'rZ=Wo<j7&*$6YTQ;wS>Y)i>6SHSeqX*|i<L+0zO8L<;+w5TBs_t)5nN6DsC*E6Kp<T7Av4EPUGXtzyEN_vgL3n2F2R{@DtEWPBa#'
    b'NQDktG}DPm8-s~L*J~fbL(I=Pd&QZYc@d6Kff*pecG8t{jx?P-xQaaxZ@a35tNgj=k87?mjAr%<oS0tK!jjFNxl=At8jMd(WQ8Wr'
    b'aTy<Z>ZS{MXd$8yQ%zPDl4|9`*eggQ^g8CnSQhGRwhJ4JVUM2SHx&rBk$Nme`aF)%=Q3wd(|cs;ctdOr3>{wSm#-%Zn)sK-$WgFN'
    b'rDcxU(Jhff%F(omFzRqVjhT4&!9Bu5=QCuFMMrD#oayFb+3m_P^`>$d7gsC^Rk-W~nqT-~zmg$}sAdW&1nW3+IYtq!oYVnjF4fQ~'
    b'$9+a28uKMyt|5meU@sq9>x`Z$XeSFJs3C>x%a%1Yyzwe#K9qCS+@}|~==!X5<J!ktE-jC8!&AId9i6(}iS9airIU0P=SGLHvh7_o'
    b'>7FmM?k(F>yF*owD8{|#i%0qF7rnUXm;2>>qIk%<VISb254QHL?j;#g%10Ob9mp2;hpIHZCzj<S6~i(uW1$NvwkwS#F_)-qn~m8d'
    b'`LH+YSz#M(our965V+PrCfGLgJeL!x9ozhdj$fFP+$Dcrj>U3yBD0XYbDjha>1y=)z`B{h_}0pC(appUMwBWEdMciCABk-?GGp4y'
    b'?VdE%T%o>>g4u2cJoty`Mw^>-{S4myg<B%&$)J7=Y6xv`D{YN&c(Kzpk@4B$VcBiP*Xb2x&(UjgS-0pi2H$Q)+TBm9RU~5_4z&Zq'
    b'ljG7_qS~ceu8r*uXslA-vwop?90?$~<=R?nQQ05&xrsaM*E4WwGbbk{2?;MIOl8)WA~73slaW5(5R=pC+|27KeB7h0RsL$A7jr2+'
    b'Oj>7`?fH}h@if%FQ1N(nyS^9W$whP|^y2NHYM`A-Bff5J+k}2qfc*fS5yt#_wug<-Hn5#i-~>FA9!_L}K|nR)9j>!-9wb^(o*oq>'
    b'y8sH0^VZp1jTDF(#6wmO!XwDK*tEx=xWx?HUWjN+0#s?79CIm`@aPTY(evdQU)vxeL*XTD^$O79g5bX?9~m)7ltNJB@q8DVE#reW'
    b'PacV7K3)*^qE8uxbG$r^0f$y3(K(;##@4JxE~~ggQ1z`fN-b6=*BPdZYSf+hMr0E&pB~9vEtd`Ra^$%VxEJn=lHK0cJ@gu_UCbWV'
    b'<L8Ik!l<p%aK?NrFL$cx8ZzG>4204=buJ2AE?;ThhEi0-_1vPRjHBInJ330I!TRuOT&^Cf85`Lo*?KIj%?Ic$PdbE=GUzOQ>>Rg)'
    b'?cIIoChFE7BRnd`hh$&7+{^y<Y7s!=Oq<F58SAg3ezxAtZLeBurvR7pu_f|dng^Gu@uq3%<z8c#UumPINN=pLHm?_Y(u8SXLjlZZ'
    b'hypojOUYu|K2t@Dh&bs7JJvFap7Cm0as+gvR--|rO4hD3S|5p`t6MM~ttEBxB6kgsEEW-BUMrohnajOX*w(ZBRRAO5I+3H+r?<7+'
    b'!s;+o6tm>juA3#i?G59%N%bKx3v^NmaPG0VOshGzR2Zfb3Hazm9(zkBJ;!@Uo6~NZj4xy8bQ)t4Vv|jumsSQ@8BAk3Ng%~y*vF1)'
    b'%BmrNPABeOSGD%+TyY95Naz=;R5e?6BiV*kPb{X~p4k!@cg@@f<fxytN0EY*b49mb)>$tJVmIkNhR3XdSIl~CwrZ2wx*5M!%1MSp'
    b'!+H6q*7%a7%2llcim7{_pOzC<n1#yDraL`tx)nMDGkwX*gJjzZw5?71#-q5(;~V9W%RidASc~S|Q(2i9@pJk9C>JJK#w;Q$<Vw4V'
    b'iQb33u)hJe+l-?C2$hUo2HaN29Bd@lzNH0U;|^+Sd7%+;u5^mE$lR>D4uC|JftMQlr^<~3<Lp4(4NhBUoMv~Ba;8zru1Z$76GY-1'
    b'Ox2nJJVWR(FFPiFlJgpxaP)Mn-@2d)Tv%HdqK8L(mbZ3D2Vn-_bcN@T9LY9{GRfvK^`Rr3^kcO<)N8B3sv;<j<aW;HoS__LDv`^+'
    b'SGcsZB~4cf%T_Mz!Cvz<qaMhi%1m?0z#7B_aCUS9G@rQji4igtDzT){sUO$1+cpXJMO0<Wr9u&omvopJ3B~#4CRwvn^_J+96*1Mx'
    b'dUvWjpI4W=*$z8(7c#sF_vww4$5m_OquK^Y9V)wiwnbmF8Od-Iblz;V*VxQ+0~psCGd_zV99>S#T4J1UriJ>z$yvl=waB!ofmjP*'
    b'lu?iCMd`}=n92;@MUjknr|~r#?x|=C`OU2;XH#bCV2<Eadb_@z18AMfMuxd0fJ-$~hRU}T=;)MinBS*mV0v{MqEy*X(y}%4D@IoC'
    b'inrVN!rx?h#jT>5e7wjkl$?VEwoRC9m{ay%Y@O*>{bgH13mOuwvxRx!k6Ac3du$<Xznk|Ykxx;@NH4;T_h@@bj{#l)0FC9K7?Ho&'
    b'h@6WRI<lRfOySnX5RNG<X|1M{IFwp|>W$z0+}l%JC2cSs;U%vG@a=i~Fepb>PEAPN4$yd}kh6Y7E!}f#qjhoJQq67YO?NWx+^$vI'
    b'pXK&QWK#7!u3VJn_AS;Pkq>HE@~rwz9;X!kB2_Uk%qdwF*>6t!8*18E!{*wtRVRv?*}^`@8q>k8-a9rZ;T&mHb}3M+rPW6oJj#{6'
    b'S~LCKG5#2FxmDo=(r%|zYR2Mit1%ia@j53gx9lYw)3lNShnNjnZ#putYWMq&GV0e@Dm$2tR*@uv&*+-cy+sr!hj+*TKzh=A<HZ}I'
    b'btx(qC!c0D0*S4BH=UgvElodd^TTu&g1x*}nD<w%l<<o!Mmn^$a6iDheO>~>d7j+1Q+xH?<@@!;dOBg4{sbGY&p2MlKFiqYX)R|`'
    b'dzOczY-?GWVpZ`5t}@Hp^?K3H76a)MZ8XoFPo+L~vHPuxxJ#_clA$=@G@RFxFF@x~QLSKeGpg6xJ#f9eBooxulX=cMbXtRfyuo|B'
    b'GsrBEOFLRPoUrv8q?1-Vl8%%cB`*0Wa*3lTdeUxwIWVzaDTDAeG`XUNx_H61*U&cHomNtsnZ-(qU*T1`v&WOgUPd3vl3&nfI@Fk@'
    b'G5&5(_s-Y_`+aMXC3gGVDYM*?{%9(9dIJfb@ij~;XEO|$ejH|ge(%Q1a)FseFtj^GkT7mcrYA<ZQg=1KQhJ`6AA62#`7~ApQrdc0'
    b'b{9v1jqTBme;TS>=5grY$cc&pomnb2m{ZMN6GyShNshSq_*Bj|Y8h$Q(A0_09~5-7nPRS_5!&JS?!@XqCZFOCWjI+mWL$DsaSH(='
    b'XN#D3@zo_2x#M<<cUv-<90FUIT+e~_v}xZf)!fKUCRCmh5?L)$2h!4`5@`yD(i{-;^~%t}&QOOvhHC+^*e0STZs+dTJ0#U6F(c}Z'
    b'Jg4LBs(EnctuG!_zWVX?M3kUCN#W|k9smo5sVdr5KFw1yV()c+7MU|kyRsTzMlMw;MCD|$l<eC35nlH6aBokX!C|G6o!>_>(%vLe'
    b'cQ98wu{TdVi^P2p&Ez!cT*8LZa_LfqdFKEtx}Dke)azmr!Lz&DP!`O~x!bjv-K{lEmo|fZK2@QR7IAh;oRpKYOt|lhn_kCD9`9D~'
    b'V!Yx$k|b(uqD@&|V+W_OoYe1w<p7&7sa<V7TNuPFE!gCE51WYqHqHB+T3u@5tnaZ%A})LV15VmXZo9wj&lP{g)^JGYb78%lOpHr-'
    b'avEJ6f&4;yq;iE4v)*r-Aj{;iE)g$A3tqy!)lb4TdNYbTEv@^h#k#)Hy=2nZHuB5IU8*ad#PO9{V}3e~r}i*M7`m}Y)iO?u@<)g8'
    b'GS01%%q{x&V)Jl}Uz5hJRqnAqg*3D(P@fR6kU<!H5#tHXXk#lTZ$}Ffa`)HsQ*H@1QcA9TqKL~Ty)TP#p9QOfw0<3&cEYu}z{_i8'
    b'#a<id5Fd`x_HjUUu8Z{}+HYessXFm)sU~7Zj?J3iJvWw+d0jGcYC+#hhB>Qx@pGScIS?iJMz4Pkrb3XVW6EKgvGoO&s1z?Z&3hLv'
    b'%G>dNdxqB`KHU1c>A}5i(}{~_o1{vhHZL6kWns*z;qX$tG2CWykFDVpX2nLXoau>${l=L0s1Z<Cb&_u~n$wR@QQ!t|_xE@OO-HL|'
    b'^+A)l{xm1bl&6K4nRO#)ZmL%Ei|7P`Mb|L6ZFMxsj_M6mzPFE!c_hwT=VcGcV~gDi8DT)A;*JXvE^+-cvmM-gqL&t3@zG{^=iHJ6'
    b'd=N<jc{`6PRTyg3uF5Qo8@@kD`m7c&C5hdTXq;23UGm7NocC{iG$B_!?dTsBs+o$`HnVPV%k&kzKRe;a_EOokM>}Sbce#1_%tX`s'
    b'{St0h>bqrYKUyoNW8b0}+1x{6ZLYVH!wZy5j8tuxtkR3oFtfJqeshMbJ0fjJV(+T;S8W(rnPnbgXEqi&r#G9`!!ZCgK3t>rxYn-B'
    b'uCNs;E=z7MS|5zaWT!U?JR!-keOPXUdmX{+<X}MQ9C<@rE*@d7zB!$*CbR?BcBnPMSo&IdoOKLPYxkH7#?lzm)QO@`saVCk)0<ll'
    b'7@^zgTH?+TK!PW!4$14%bQ`_l6CQG^@O2cfNx5fh^U%ywygY3aYh-rnEiV``O6T!$OOWW8T3ML{kJXOWZO?K3wb7I=YSr<Mhihpv'
    b'i_x<}MS?Q>U3bk!4Tp|0QxhZ({Io7AX&1Q*4oZi;%3^A_n~ZOntf^tkOLtZRQ)TT@Sm~29z(%__2jlE|gq-a(1l^sQlP22V;`PV1'
    b'mu>DMbSvs6sbdfCxZ|6bgf}sx(ua~&uhVu)8P2+(IM@Nhzd<<L*$G{$p=xridq+Jd%nIjv4M^OTOGY>aZeL|biKW(uTj?dzl2|wf'
    b'^w!BoqHVW_<n6QoIgDgzN`~MucdSNZr=kWI+=TV0YhskS0jSan*By5L5tTI8zv$q~@bT$p0b2`JGaP;fGX|ErcbmI;hP-z%xPCV3'
    b'dM(j2>X2r@1hSr1Zl(F0+gHdzNgEV6&8B)0Xg!U)@tQiL^_x54OIEM`#Vf&5@lN&%jqJ|oREeC}4cFYj(sV5X?98zX6(@QiTS^pI'
    b'EaT=Tp1x$LEqhwe#*k4_OKxk!KBO3<Y?~6EpZ1*wFpjj`sic)ft<g+T-hnuTdquMMgy+s1TGV%}S*uU3w%HVLV!+KNG0RK|>k>=)'
    b'Ca%M?+bDz0VJhdA#Y1bu$N&*dS{5dIBP*50tGwFnF+CB&&xCC`oF&_CK0t9T#6N^RSajU18+(;>j@tGzaGFi2)5#;;W}7T4-FCyz'
    b'RGrj0n_4BjEGK2H)Cn4$(Cw;~%I#@ARz<GWNq01r<W@;7?~aQ|GNo1fwYoAr%2J|&+KOR>e={<sNX3JkIWKkR+0AX-t?7g9rZ>0='
    b'k9C$y*QeRGQI%+JKlQF+E?yyf<54%~xplnn!-Vb@xsx<0%I5ia93*B`ohr8q)cIT{xQ;NNiH((23vpD;8TVVw?0MTd7~S%!KJRb6'
    b'(@NS5$8J1dq!ahyfT^IcdUd16Of~CpMY)w|@KFPo6Dw=CMcs5WQ`PWnjYZ>ZS@2M{4p90YjR0VZJgbYk6AAl=K#ncTmNQX#zvpDL'
    b'V2p?@7nvSi5V+AWSy)|KOKk_zWHw&Q)Ul}+g9!4{>JtTBW5`v)nrP6Zd)$vE`CK_pNt?;dVvFjkIl}=a!40?NV#q53?q{&<#+;3d'
    b'Y>UkTc8HuOYhj0Cz_mLEZ1u1bEIIFFd$^q`5ir#rrPbVa1rfER3oO_hJ=~TywiN3yy$iN}xWan3-tZ)-R~w$;jkonpxbAS#x_yV3'
    b'7Q9ZpF-5kqea&x;6`5J23Nh}6Wt3>_oUg`HN>7@*T|9f(%dS@!x3*tjt(ax~xD)F=@6caR@Xj-RJ99(`#n7Z^DqfiH`A##o4f|2Y'
    b'>@92Bj}?%fX%lsjGTcW3@bl+|%bR>}-AgR9g2Sue)oI@*6K`_pA^2i_%I-M;tKH|3;vBDI9^&;*>~b@RU_&MuI}N>NpC{*q1x{ej'
    b'=<>x&Iss*QUgo?hvVo{YwCo|X0aHB1hA9ZG*Btt$)Db;P?SO4>RX!s|t%YwEo$En|Ve>X!r_0?7#!h3tQ<0gKwDQTCEfJ+oy_VGu'
    b'Yia}G^LD5&Kuc1ovDSEO$G9DtZEJwjIh6$thKc}`A$mS7sBLZ8aiKYhu^W0-DQvct^yrRN-9#aN%PY~#(Npz$D}TQ2PZ}N_jR&Re'
    b'I0G&4d^Hyd3h}T9+sjLZeLf=0$RT-(dF_cllk#-Acywb;GwE}jJjaO=otUXm#_Nucn1?>jd3>|owYFvdxQ2}Aw1p`Mc;?6KsOyya'
    b'N5d=ewZ&=OJeKhdlMC0)_aj~<$_@N>>W=bqhmop{gn3~fb@NcdBUOC2$0<G|bS#X3$nArJ*>Ux89n<=V7*)u0TTEtV*))!2&xC&Y'
    b'|B1S?on@6E_$)*)f+2Ai!>%9-%BHw*0V<0KDvBtG%d?;F-1uLbnCQSvbyZh)&%}gN@TNpal>P<e>Gm;@%=q!+0C@K(uCgl*e3!Ps'
    b'VDlkXiNv$ce@vx2yv^VBH`~`btLemeMAxZJf3Lfx5K`sA;>Fo?t#}X?0yM<_<I=Bl7I*M!JIN{Y!x&j#%4*tm4)zbD)<?n^H!4vR'
    b'0tdB9KZ);s5zyc-Fzw*wwb{qm!FnHM-R=6^+6<=j;~F$vWYq3%&4t7#>=XIE@v7xc=hWqdW#n`dtVGiwfx1^VH*{rHzWlqm`r$HR'
    b'wF0JGXMNGD%@8^avim8@=RRKSk@n{Rt$Jv0=)a!Q_!VZ=<x&gsM&CX)LVY)$&Pxtf3L@-*jpTwa0VfD#b9P-{TatbR>i4O-{NZ7*'
    b'qJyd<c4fS|U6+w#2jQ9mfxsd@e4u4f+Z{fKOo{(M%+*;{S+)`*XbswuGB2=2BT<)8Zh+Y|vV0IF*=V~SbZ<`Td>({ISKAJ*@QYtR'
    b'th}eMxc_Kz;tP_ehnj!dNmGFY@Vhs6W(S0{wi&-77U1*+G}Ll!Z^P5pql+Fh{#<OWw(C^!s6&$id_|)=w544d6p1m`RU-Cdy^FEz'
    b'{_wCcKljIzW|a3OJR%J(evaO{)7Pstr{8;XucGu9qfSEBW5Cw!RIT_~tyFM3`!FH$tg+|W*J*MHs8U@~qA4~al2W<ImmmI5<Y2{1'
    b'_a@=t`{Onrz6alT(R^~*a1Z>t5Orx?{tkmfHLu^9_NZ!iroLer^NLr;iBji+J6d*oU{)pG&L_k>q?}<cJGVxj@!lFPYFmVx{qe@p'
    b'y=b_lqpaM2&oBqs!ML6i&R<9^OOTcGHO&p~qe);aZh`qO4FBGoohqSQ7O?&46wGECHfwcl=lIT>20j_BnY@Doeqy>5GMUa=+SqSL'
    b'4LQ4jaXVX1Z1R_%UtWgUhWI?W57Gu1yl4qTqphza*u<RATpm?tGV{H^?+^!#psU)wc?)ic6`DUQdIy>z0ooQ%#-@JRe7ipCq6$?X'
    b'av1Hw8HX+><xL;n|MG{8N^qTaijo3a&cnEEUk#mtgwUOK7~~;bmw>-ki>H297q`!a6>Dy|XkOeuZoCap(2atmu^04eW&Bv3(;GiI'
    b'af=JDqWk4W)V-2xp!MkV^8yHic=gvPvg#T6nI<bes=K|f*K0Cw^&W+MTE&RybC0X~>9@P*rXjA8`e<!Utb6LwLXB>`UMzt3NeX(t'
    b'<}r)mbn4ZvlUPik2<yKGu3!2+Lo5)FxpKU$TIwI>mM9H5l5uDCnZ2$pt_kmq^`R9V>C)(S7@n3ue_vT;=8ib6$4#u+sf2m83dU<O'
    b'k;L1<3+i2GoG`!vZq^gCkUK^&r<Xr}*~Kr8II3rJXj?`AdrO6TwPN_uEJ?@q-uu7Sk{~uB+!xC4rNlI8)79Nz6WCzk^$=i`Rc;2-'
    b'd2IHtQ`nuHi{ay)PbRL=>}{C0`gKta_~pz8<r9R5&Tz}Rsd|u-;4>K7iIYUCVzGhYcBN1Cy?)L5ml-$W>=?mHz*qPl%?Ya<hJ{Y*'
    b'&wexHB&)0j)6Zp#o|8S=b01kvghu|hY}V{w&cS>sK4Ju&LtYBcWeDs|CIQ>E`_Ef6pVC)Ec9skvn@56HL*VL(*S7v3>(<KON!62<'
    b'5BhO@t?Hd;!GqgQiC96$(306Fy7k2B7^@j4N%{4sh(m0M1B3koTVMIkgagDQYB0#k9i&~se^uM`F2~)EWu+E(X#+5rtSa5pJZVY2'
    b'*-`qE@!kT5In12qG|8S8*_f2>`-O#n(uN3thk0A+{rV6$Xsve>`N4U}XPX6e<pNXU$7<C&=yXYbY@5vh@vU_-o0Rj_B`l+(A{~{1'
    b'<lCqr)}^bqPZOz+<jTMmjd_w+#+LCmtGBc%0+h5TGER4Y+~zIfu2#+yxtf9Qa!CZ^$<`8!4MUa18{fj7!Me6FhRo6EqAgLLO`bL1'
    b'Mbp>#bj|1Nu<;E&$OKClX!-!h#(-5mdF7^A<)p}w<IpcsH2Bpz7WPCm`|f>XEI5qmvMv6rH%FpNf+TcAW6j*Ow|$A54sHVm#s#2L'
    b'v+Ri<vj)5O{W2Zj<-uHA<3^E;(k8pZXmFX#oh1ywT?%S&V`qB#dD(xz+g~Dmo?roJy>8#0k~V&P7e@A6v}&t`-Ju^fg?j`g@GEb_'
    b'Q_3Mu;FdR=Pjy8VmUK)e?W!LQuJw;erB`M!oQC4|K+%MkE&a3IvW?xpej;EVs-_CM5^)<_h!N&`@8&7`ml>7o{<PDaLEB;DlD!&f'
    b'T;V#pIJ@77+ph0TR+?wCfABl3e9{#er=9t2Q|_c3yCsrMYZKfXu(!;=Y~!cRPok2C$vP%RRKik2@g)t&_=LxmTe95WwerR3s2Q*e'
    b'xvFMu7N1q{06yBvJ>IV-jx0d=UKxGY=#a3HsLVBu{RDaR@WH}=N9wud&kk;R|J#Q^7=Vqr81ySCKbjD{=`>pB`S*DjseXDx+i-OE'
    b'fJHno=7#iW0bjdKpJ|HtTRCL39HrYHlul~J+mDW;8@EacP7<@W&X@0tNdF4+HJIDK`uWt%^>^#2-M{VkBzVcj(5q;Z*wezp%NEz$'
    b'-A9qy#I3a(!rX4vEFBG>=}g0C;na*-b-<?GSL2LpUsqDn_m-$%-Q_H7q7TTt`B{lsZ4K+k0j>e#r`+5pqx3vbY8N0Fhpn_&P^!~;'
    b'-L|q8a_dL^IAf<yu<`N{d3Z$X$FiAZ+udluoP#$_=B)OlLG~h-rYY^F>9b5d!E(6!ILAk6{f~<}0isk-Pg3(Mt<UE%*BDW$j5n`z'
    b'*gd+PW9wWUd+=vnRUiH7oqI$Zr&U$n0Ht69EgU&qWml~ZO3X+wfnB^>RwbwNyc6u%aZbYL8a1Gc@avUUR`EM3>T>dwYL7Ltx~#-X'
    b'wV5mI<7rjVd#2rPwsfl$_C7v`=O^(!@D4pN=o$zy<XEfHd$9AMVM>S9BN<(z7rE2_NalzX*!am&N5%<$HMdeM2#v-E?q!$rJDb(<'
    b'hYHDaNHb|@5q0SYmbO%WeND@y8t-hBu=ZWv?~hk<d1W4y;oODJBccJd^^v}2dyC=LyO+hms<a!RWtPdMX!iNlaGrL`K9k|*ir>us'
    b'j;vAM2TU+z{gdaG_M3rDEGt#WZL@0g2%WL=sOpz1yhoQjyLyU&QXhA4X>fu;FR=f_<zSm}f-@54Y=m=G@ID}w0{HnvBYAf20W3pt'
    b'GogC_X6Mhgat=5yc&u3LfSCP*?zoCTXO$g0$_CtqYg1Ck8_Q30(|C2a?B-S)W`y0iAD?ZYe>+Uk=f#udHJ2TYY%=2T&aZdr;El>{'
    b'aoVh+gwpoe{9CC#Ot7jMw?AC3pz@F(cB;Fnv**f&bm`n=4@IC+>NiSm!A(V82~(0eHabL2J~B7RPVRF%X{tvezgI=(UQ5K$uNI4W'
    b'(g58jD&tO@#c}j4A?k8|Y!)xPH=os(!=C7`aywf<>QO$E`KZ-|hfkxo^Q4{no@zbjKJ4F?H;a91aOhh?xAq;2(b-C<^tKLMz{ZBZ'
    b'd=#QQ?aYjiw;(<b%vD<ElgjmRgdb~u*IobVz+P3^AKtWzaan8q_Pe9TchYj{P8XdFwtbVE<(2a=RWCA?R_1c>0>;8>c4#*+$ENHB'
    b'@U7i{b+C$fJ{pDsHrku5X2P~3ZfF3M-yg7Vr}nn;s9D*G=v`WZ`^L5hiLO=Rw_U<u5ox)0B&?dEro7gqc`vyOwnG55+Bu6QNq|Q0'
    b'ymY>8MeD}_R<}hfv1z&fp}yDN$i6B4(^wAn!l=t!&wuM`N!lIBX#CLB!`1?_KB>IBT!8=0jrS<SpL8l`q{?o3dhJY^mh(O<kHz%w'
    b'qg3<4?ObVoelxgs>v;ItRol1QweKgOwTCC<?4?aw2N#WWuM#}MO=%s}rqc4e>Lk2hO=gy{ZIL2)p=&S6Ueo?U$rh*DLEOtawOF>;'
    b'>g#0dpv#rOCCV*Izd1|C_)oUOQ=+yT8gc>d#I&-DnAriJs)f@)cj5~S=T$i$@gdnWS1o5VDV$-<cS`e{W9bzN_zWv^5C^yZja?dW'
    b'yMJ^d5R=6!v8<BVV@31hAK&QJmuea((B>3=D3AD~b4n*oL|oB_?~%8$HLO#0tlXB_3VaBnQDf9G&OF3%E7$`W-!nSv-FJ;+lP7RL'
    b'51~9#PJZ71CZYVDMBMX;jeq&x?AVDP)N<C!I=%V6tI<8ATN)nYvg{qfY4rWBlhiK}w8S%aX~k~2&wfIkf*pFm>Zqs<qce&7`}?$X'
    b'xFIA&ZTS3Hx0*v)>Xfd4Aq_Yo|J9{T#}=1P2OI9av&xZlQm0>WIC!(w$b|CV3iH<BinN+*_SG7{T0YbV0e{?0)5euC3W!M@t-K`F'
    b'Lw_5csj7RmVcXbG#}6YGNhii1ufgr#tSV|^RvuBwAW==DX)FeMsl_Z1y+g(nt8l1wkpyDal#)AO;U&B>;FyJ==8B$(Wop42S9~-W'
    b'W9hti*`NRR>^qc-^3@3r&=oP$q$;|1I{fDoom^(rsO@og@mba>yEs18WM?)kt~J?1yxwcqT)2T3Cv0zbPPuiM@__XU=Eut9VFy7r'
    b'Czfwm+yC*dDz2=ut_Y%@b?)3eGXFb-Ey(eHn&=V_9$s`;ZDcG|M1j?n2qx#>Z!^EwO1tWD^NwW}Jxwl+rq;dC77&Rt942xz7HMLu'
    b'Q?D)(%dOq&gu{KZa;|1Kpn(ZQ+WiB9QdCXli}TaVLwSkctR=GB-0}R~5>yuep(-{(grEtBN=lzEmGyMu-f|-wEd(#dPrOWicjdWW'
    b'&85SpoikQ@@kEyO%DxpZqq5b8-Rh9W=yv0rV#{7@-2eFw{mAo+V|~9)`N8Bpo0^BVc)7r)*IJWrxO`rUbNB+6PifT{;6xMgfm^3l'
    b'XwaQu&dq1%f;7PXx!%aWiZlIF!#2{@5^va$dhKvh1I_IGPn);cRkJfbRDnOzc98CmX+4e7>iSwdwfzC^Eo!aS-SBU=S@%z7fONyx'
    b'&gGv@%HvPy#v6IuW18cu$@BX1+#xGG9J6`uiO*+IJ^V$wd$XPVdcd;|-<D)!WH$_BBwm;035p!SL33{%F5s*l6SMX6(-rM|ebIOn'
    b'%4Auh*W-g%{}WtEZmxz}ZP#}Z+9vtQ_5k`E{+Qx_M81&0t3OZ&5Ab{V`LKe#tA3E%0l8SCn)~n<R>YtQ;msMb*LgMoV^l(b<Xz5o'
    b'*-}{4+D9nWWAK!3sb`F;0J}tJZDgX-Npq?B65L+KD9Eu#awzN|F~p2XIsC=1)j0+2$D)5N4XEcmqmF$4qrYXtpYq66XX6UUgv8S='
    b'D6zfIJT4~=;S(h~Vt<FJKFg4lbD9p3H=mZaNWavzH(EaN)g?8V)QvH}=tuef$2SI69CIzb?x<lkKpz$Feq=_IqHV9bAAWs+C)3t6'
    b'GvYo8uwx0|a~r+^cNvks5B99bl5-(N4@Fh6w+S>;J2UAmtRTF+(<HXD%I~b`bq7D}^+~};w-WQRk|ZnjANm%I3G#q{kMo(fz{|(Z'
    b'bu)dX)hpMN`qfsGLilc}7Y)!?xgKy0m@)8WN8fLR=v&xe^Y80e+^?+GFOZxDVzI4Jw;$hd;k9ATyS*h5wGpc^qTfE;KT%72IKD=;'
    b'+<t8o_>sk`0yOG;(Q@N<Jbw*qyZ48=_0W&FG<REQ>>T(;Q*A!yQFy?C!`;+hBUXZ{*WHwje|gc%6MN4J;kcie%ruy~$k~FlVIUt('
    b'W{F0tRm4zXYJFOrUOmd))@j+<P$kGTA!a<@Nn`wg!fEXC5z^w%(Fb0T@9(9&w9)<II3b|$HVxjt^Tq7O&Px-;>MU7kv2kje)ebTf'
    b'!#D0n*v7<9vjO0VnjG83sno7rpNe<iFJXmSEZnO8U1B2s9doczJJ!p>%4$X4nA!`#>9MT%Pu*)re3$ugo8gx~?VII;A(ae!GV0$-'
    b'wsif@rog5?@@SI#^wC|r^uB@ZguErkhDUvIu4X99Ruh^{@Yd;i6ZR+f(*}9wJ4%l4TKgfx^XcEwD#P-FMeH93aMC69UG~64nXUOh'
    b'nd7Zrra75zUzHMAS|DV*Jz8ye@nzrwR9D6FTK16o>m2d@@_iT*HjAvteCE9jdGDH!WVl`T>YF)vy5Dsw*naO!Z}7w3ZN=>l4(Dfv'
    b')jD>)l?uh(AASGya^7Lf&8B<9R1JH8P^@;#s|i<nKKGxYHs4eRa{DMxM(sJ;u-DMEnx2g{Qmt-Z>C?j*B*1oA|Jd#DSMJwObeDT&'
    b'%Qhp;KUSJM%)tvv*i|aqZ$8zDgQpzQeynl_jYX<|k*??{%Zf;Roij2l>NHy}K-&^VbvC5us|{tHtKzIA#^LrFF-~`IzKw=Z^T+4a'
    b'#uGFdpaamQ;)#PnI#Z`}?9;5y=0L%O2{u}<WPS0~ko7VWq1Mu^V)XF4c82d>k)zo2MG8*Q-!KjoVQvC6ee(RInto%6o)QTZN4W9J'
    b'&+}i_tDWxrt3~<wY&?f&NBK23Wokd!j$7Nr5ApTo))bZ3c-kSQos(2|QHLvdOgpVc)64b3UumKvEQ`m>zM;Ld$*$p(5H2%+iw#F0'
    b'5bS^R9F)pTVGX1d9$#e_d+xPP*5C4D#OXoZ$_iiW$MM3h*Vdj^b*N;T+&=)V0h$ry^isyFH@CMQKAPlsB@$;5?uHXi_G%aJv*m9k'
    b'O40zVBK~;q+<o7U*Tc3sNhVv2*wLHysA8`iqCZ)mKqP))^%^7%=GNwo<!<+=)jP`fex|bP#u`xFV0MZKjl0yz9(L^5hvnQ_C!fXv'
    b'el>^VX}BBh%ki%Urgn~-L%!LTm+M7>PqsRJ^_zTV&X?YF=&l!o&S~Hxmt?nDCi{^Xe}rd6uzj-?;#)5}sPmG|1XlcvFm+g3g@m%!'
    b'I0RaC73|Qc9$|OT8~tVx*t~GtU1{UITy$LLoKI`@Ei>4)y6B};THTDpuHlFwc`7C5*q(0&f1>D5yZ(u~^2IsFkM`W!eVE;{u{MV('
    b'Fq!pU<G2b2m#X`DoT^QqI@|`oyv;iM8WYwtD_&2(d)DynYgFGykZNO<uQ|DKu=vFZ)6a{dJWwWeq<n1jTi^DZB^$Mew8F8>P1`FR'
    b'4ee+8>a$Vw2iF{R{exXYN#_0TYF_;KA+zW|*%Q~pA#=`t*BhuDX6I@9KEF}XV!4?#NRM6+t)!%ccFBHqp|u)bC@GpUqnaF0xm&&y'
    b';QUBfr%RQqq9Ig`d=_=XqWgS9%|BFHJbvq<*XN5<?|sWkspES%&00h%zR1sl7>>tUR{bggvvY#DpM2W(xj9+Z(z5ET8nWYU#?Z5?'
    b'MPJGx!67z8o=f}CKY(>Z8TX*MN=P*=^=@G6hldH8en=ukBoPNAz07mY=;fW*qAC@Pk8|*5KSl<`3jl4NCFzC6lsg9)c>lqW!!wV-'
    b'G?PzS`>J;yw$g1m+Ylve#C8_6eo1_l#a=<3|HUtQSFeNUXMkcTC29gH7uu|1wTA68lc8s!*^^Q<7}(Jh!HqGk+We?~ACsdJyf`ZR'
    b'E<72j``2Yv{lEc8!JDktEO~vcWtNLuvrGiQq?~ELn!t;v<R{~jobp+l>znvx0hC@v@kkvNB!wnCYKhaY!A-`|XW#7CG;|B~#_>*G'
    b'H!hn}`=yY<E!RXgzSkhp9c+gyya$OX<hRm0Q(sb0Ppkbn+Z&TXr#Rzpr%cnYEge?lF16awGbrqj4f{K^Af^T#sx(|l`%OYc^z*Br'
    b'=I`!qww_$-X>f&WY5Hg!+^R2GjpMw)R>??r+Cb~M8qKs=ZytVl*h=lUVU9G;XN&x4g1S|VDg0_X<+3y?rHrX~Hh@}ZrE*sGLuZW('
    b'3;Vs{o1Y!91y*@EhsGzI;KEI>m^tgIKC`D4QH4d(spu)AE<2B($6*6E^ROZSy}2rwD*T!)yP>2mVIYQ3Y)<vx`O_!r;lfduf6&c!'
    b'v6-S=UGT{XL~nMS$7X3T4My{Gr@KukJg2BmdSgKCge|6WlDc<mg8a_ctJ*{BOXa}N4&UCcS;iX=+?un)*l9F%z#i4#B3V6_^W$yN'
    b'UZoGVcPKX>ui^x^B=vFHpvONJzMD_-+-`5mZ^D=tKoZqTN<IG*d{X`9u!mo5&rSlRGBjFF;EcqX=c8dfYRi6u?2l(UvMN+!@4n>n'
    b'?8ZFTprWEa(X8y`w6Emx@*9xQ{izXu&<N{FiMV%b9~pe$lBP^#zp<MJxC0TW{PO}hVIQ5>yW1sR)|8E8)+!dw_q#RHYWs`z*5eWy'
    b'>I1X&2;!RKV-7p}%Q*EWn<Kl5>Ei2qL%Jti+UvMKGL_z7@(>mr>viYN^t8nbyGRA}m!B`y!)JK2Jkm6cTkj#U_^P_LfopecES#Nb'
    b'UC<Yq9SN*l#g>g>y*4tG+c4huSJ+o2u_JLTZJzQq+-J#jsm1_#ACUcbv0oblP0kKjeb4AW4$!SRz$p>*{Rr2v{T{1tlTeo2;i?+w'
    b'$JvU%#=TWXRm?2a&~trW!ro2bP+~j2)F26~Qm$!maBR%ea?3fmDtkj$6}Q#!2#HFuGYsCN&h&S_=C>02)Lzyev=60s*=Bpx)UT!;'
    b'a1Y44r6MEHtLc&YCw{Trmh<#+t(#EN(dcYn!(<E3Lshjp?xhq<{loiA2lT@82l2a4Q}XHYs+BI2*UxKPB%u=PQwm#19)h$VAMVkp'
    b'3LPqXLW5zuiP6)zO7<#iWFXXwhxNz&a#|lXso>cjYoNPG2|h-1)9)_br)dQ!($9qYs2u|39^I;yf?>V?t4qOLYn8EIZPn*rLw>I{'
    b'^j4)+X{;gz?&WZ)&J(R%I(`p_E}7n8n_TqoaD_YVpjAE9UH7Uni)JvtwWib1?!#8AdLy^?q2S~3oDarfI@HZyE%D)em_#9xRKq(r'
    b'ykl$J4V3Z54Wbv;CEnOh$Wy`fi9~+3HZ6(nk-77!gN1rirJSbR*`^nUBs)36r-rr2joX^jhP4YDRIKN0@nuG+zy9?FjC<SpCN3UF'
    b'ikX}$fUZ0WzTbk-o;S|U73^L|Pu*?NSeV<QJQ23kl%G!$M5nIvr5c`-CRALLD0Sz+a%^Q!*{{E+Lu#x{u0Ult&l)7N`sX3e+a=C%'
    b'x=xb%uO!IrCfV4r!D^S6zry4+RIB#ReHWg)lbTRBq%NJd3&4<V=e1bReC1#PX{pxW*4pW$GC@0_3}#iS&qwEyorN3Go&6E3pHCDG'
    b'zLvN@#KLqt%hSbRLT{GXoX}-vk6MfNkqU&WfY>wn{l1b=+q$~$r&=``toXbqSI)}rjnefIsZK_J-RLNek8))kK9>rvRbEH2eU^T6'
    b'%o=s}!db)MQS*`ZxeMrORjM7nYx9<psoki*hi}DLR=jCioA{b(H2UuBOPJ(goGq#yPLb~0Ct$tn3Uk23yQlZ6_jK{tHK>5;r1Ti9'
    b'`TWltZAfwNXhe<<(nWU4rtXb>iFcW$>@idpi?DvO%uGaX^k1~Mx<K(TkYF+M=lA{R<PG!ED`h)x>;l2BCsIp+s6u0Fv<=iQ^#u^#'
    b'NPcPqKmY5xe<`ThFV`bBR<FT%R~+5(@ME?XCNMKQ&L`}4X7-|^m!_-sc6lEn<HX#9ureDwEVS$n^;uR~KY_FotX9nEen<5KR|EcH'
    b'd<%Z<9u*AQ{+=N!&Ym*r34?lfn(9qoq)JG7i0jW>@(T#0Thj+>s1Kr;^2qs4t<f`gS|DY0ajSb5zpGp|Km6<k&3v^$;8lsykGs6)'
    b'qcXSDTsb#ZjUn`_2^@mzhI~&-<j{U!njfO83nV?g(<9A{W*bHe541ct$MPCUTXk*uD#It+URiD-42KNy?U>34+pWs)ARM{di#<u}'
    b'+dHg?ySI|{Z=P3LHniWmj1M1P@?I$&5Cg#{U?}Xo4%?Ccr>);*UpwvF!hONizp~^Ul0l-(4e)5Z^r2Zn6`@}_ZU<Q0oGr3OVPCnH'
    b'rVR(hVtx--TV<iS?l%B}@cVBb>@2TP9n2iDbm#94Cp#g6Tr!Y2<pJ>&b9PR*87nmVdM&e`A6h(B0b#fm8cFBQ(@mSc)GV0a4Kw51'
    b'O0^4mN!L>}_>K-Z*O%<q;BF<q8ki@`Kkwm&i0;mKS35=Io)Y6=i74J$8$@Yu1Y+FaIQ-nAZ{QrQ$Ks<AZZ<eSW2_4zhZjLKzhq3$'
    b'_Vv^{$JcwdyRISvfe^E2`z#_sH2L$F#RXdg$I}21kcGO(S5YiHTZdP<#(6<nDsSR_&#rlYyRJyhJY}nq<&G5iHlUqn0c-*=d%ib)'
    b'DtuLhQp|3VlA%M#ymEoYBX~QD5&1Bef8NdLTAvLloeeH&-Z<B!_VjY`N$m(+2HdFQ*0NqbcnDiyR2kP#cXeE?w-61a6C>(>miJ0R'
    b'mumTd6OZ>#%IJIkJHL6nVmC^W`HB)ZDxF@V-yF`D)>5<MnA|dYgNthUt$`{OXD-3#%7#*Q&X2ZTecNME@A$bxgOga_ghBTz=rV5b'
    b'hmF|x-kls*dHe9{#KVJ~atBDDp08wPI9<6t8+NIGeH`ESq|v%&l1=@EWw;!T#o!3E#+-XNHoVKboiNN;_nyyMD`6T(Y<#_{N~a=X'
    b'gGRURPWsSk2#?8`*=Slft1EG5f99E|vcNRW^U<q;d8hH?qB}us=EXTKqoJwQj#YjqY-%vFT2-rky6sT4UcYIS&kLtPb&256L=^pV'
    b'+TEP)#C+WM)zUiIsOT!$xLaj8>CW1JTBYh7`c~O$c_mVs_fnz$&&z%(Tk;B&AMs^c&+nx6KFjzDxZI0BT9yW-f=O~6jU)dtXaq(y'
    b'u%5CgpiQpY#|-NDRF1oLB%2_3d5y5oW=ENqr+>Rv??^Ca@#Fd3)PI_&td9bhq$*mno7fwrp^!6q-x1UXwO^ppnD=*HZ&|BJ-cp<m'
    b'AL9I)A@8pJaPr4k@FY)B@tHZA#9q^Ep)yBYnb_Gpxqg|sUwBNlgoB{i|Geysy!&)xaWl)t7)u8)ynfas|FQ$>*H3qb5r;!(``&D!'
    b'&iyh!;2U0=cY1yqSez;qK4`U5>`NLwCQHla;l-LQ((0CAfc`d5<(JPaFXQL0k3$!F&<+W51JeLg_MFdxF(DgX1fg&sW)I&wEsn02'
    b's(FZ~LYKB6nakB3N~tfRt_kf&KYTWVWu{HMehohCoWrxLOdvAf3**JB@Sj%S{qYU|5OgJvWhW0ts~VEJ0S>TTmGb7Rr;3uaD+zGW'
    b'Be1BqA`e4$a$X9=ao7#kGsxz;$F7KHkN_@G0=ckvYQGCt+1=qsrCBznsuP+S%I*A@OSvz~6`YG7J!A^^USz~Hr6+FO>g1+AJvUss'
    b'cK)mY4tlf2Y1F2@U3DM5CW{m*I_3U0l*cl+<MwxXzh=)CKjoSD-D7s-2r7`{s^}eTck%e~-gBKcau^67=#BJFc~(Q%_se>BH{pCj'
    b'Oe~@IVD;#OWFqn2?3!|RjK*4Z19an6mj8*FX_?6%yREpp52P_M7_a?Xphf5ea7*pxyxyIZP4&m;(Mkui-7P6s0^{24)?lq8Jml^k'
    b'A|0*dszaVxm)ky7QJbQ+H*}x84fprmb3G%>0jgD7$0rspH!DzEzJ=a?ciHhTgQ)x8Q#;Q=Myb85-4Ev%c9poJoCviL%#wNgu||e+'
    b'K0dIAe6NRaBOh#0mgZJwDe$uM#HR1y>-?Av85xh}=lMyJW}#Puhoe`JU*I}qA3JyiH-uMWhD6qxU9=|okK5qVOcS=!=@gCIh<$Ai'
    b'XO6#FmFfsp(l>xR*Lz;~(1*(yI9iX|S1+V)u(hp2SSsuro+#Aay1qZU#K~Ayh4i?Gz{9iC2az6eFB=(qegAT>+8H|>timLlj#cZl'
    b'1o@L!(VBM&Cu^b)Z}dx(6uRh8tPk6Jy-2!vXt}EOFp=f=|4UDp(|LL5euza6XA6%D^F3kIY+Iv<t_q*V;JL^zKOfc*gc4bZ^&Jdp'
    b'%hW8NpsImtgH|zE^eiR`X_0e|Wn^044a8o~W`cDYjnbOH9`|PcEc$b)7{H^sYMhKqIKvW=Ym;~MFuelP?Uj*OxTpMjRM*qq#zYR?'
    b'k)C{s;TZ9Ttqv%VD*g9VV_uYA2bx?Wn7M)OAEz`^H!eaDC%Vn5%$HA3klv-lDfg!e&-Cjd)%3CI%xT$-6G|wW8lAAB_VXPc`C!#5'
    b'E60Z9ubp#%$BWZx)hUib#sRs;%m+<0sbjsXAtuwScsrMQtG59ds)x3#Il8ID9CaDA$i_Gy?h387-tLbIx`|E{20sM%J4x!Z-%O_g'
    b'b%hw!Tcr_VdOZwL_U6a0KJnqb-0L?av0TH^Bt+w0lMSYW?%P(KMZJ5@N|#fBRs^s^dr%7l%k$F6ppDY7G68FBmH&GYHzINhI``t='
    b'T>VGEh7yi6`HNF9YNxGHpMqw4=t~<6rO>>0C9B*g$BuOBV;fRq7i?p*HDkBQub5s~m7@}}O@W>(X@sIdjh=uuR3=eJi%uP%HIYrX'
    b'G_Cxrog<a~w({ONFAb|L3^~peu}AU6(yHF(USH#vwYtCTPOz_b2A}%0e!6YxT2@n*b;;q@yrU`ioA?*%2j+Gx%@PW5?tHaWS$J*u'
    b'#y<}i=%<OY+Nvtko^=K9wa7^r`1SDDfA3?YtH=6raW3$ko)ULa)!}a8jgw}3_i1HmaN_N2wPdEM=YF=x-&+}3(%4O(eW+PO#M9=F'
    b'W)9Y;dC$Gx8^33G!^`lEiTdnx*=fqF<qW=0;Nns#e<w{59uJ15{+R*he9^B}!u4#L!b(Hv1(v_^8s9FH^xOAz^=>JKPzDH`;Mc-T'
    b'p~Mm3*d2fO22{iS*E2#TZ)&va?<lvq>0kSD0ioK*<|C&h&yzXs1o~?&ZpBK+{_=vqIIDAMH}J|I56f3j7xbUv+$E<_wmeDV`<S}u'
    b'HYn@opj$V3v3fu_ev$sW7iQdSVZHs7n1+v@hbOvSNS$}QAja~lNySym2lwT^R1R0_dHqnDS&`4OMTfr9m~|dBuS*1yif6X-0%Xr_'
    b'%Tx3dCAaTMF3dT6U$<C3`pw3CJ(|s{euPa#Wmf&b6=&H*0etXW>b%?IOhq~dz#fwtI4^B7;NyLuQVU#;x6W$Kon6;i!=>?2=fe9z'
    b'<LOO*MU)nEx18Og@p*@`wdwTx_^qo{c}alU7~jEo;p1t>4zU4)2ou_r?CEP82a&(RwL-IRNVXpjuj5^Vn@gU2IdvN6s#tq_mD}Nk'
    b'APuO5mM#5Q`fMK)v-$okU*O>;DZ{w-<GnX30(<!l8ae=d^weNE=tETdhK`Q4l3t87LVM4$zsOv`w?rZCf2e+0jzF&R+SGft)xY-4'
    b'retwpefYiJjrwAgVwTOSO^PCBS8(+#?vvWDCUDe|jFEZJ=4{dUJJOF6!i6nr2wjk4yazM#AzlmR=Ey*A=7RKwZUFP=Zq3DC<#aE)'
    b'rB5+$cc+pO!kSUFcQ~G*CsRv{6!};UUdq?4;qI3gt#?}WZCG&MX81PojXYuF2s~AWH_LJOz3Iadx^rgo_&HeZ`D3<rmFr8@$7Kq5'
    b'-{8SlPQ2aOmPqsq174pjlJU@miFHKIXGlf;iw)HJ^YhKiIr<{(5wTmk)djVh?~3xW;`3dvG50~&)>HYjfcjTz&O(NHM4V+|p*7<D'
    b'uzW5~MDtPF^}l{|%>e1PEDnOcSp`a{9vmtRxAn@?xp(_l_k}M8>10D5v_l>p?mG22U`F_nSW3-6d@!OW`+htgmEk6=N2V+BQ5jDt'
    b'?5IV5QTz_mAKzItq;bAZ%+h8W+R0)EyPIuOn{>DWYZlutZ2jhbTN9NBM>)i-HhRPu&nY7}txFZG1akj`KDFI#I?&{%T=@&;3Wtsi'
    b'k`#P3%TIf4GZnJDDB<n>F#aN_lnvTy(3khG-o;to+r#>;+SB&d=*Mm9M(qaM{u~OgF0^*FzTVUymkQd)UvU>Jmso6$s+Hnu!0-9d'
    b'gH3N+6-nt*_C3dr#HC<rV%g`Yb6+$i(OTjw^W+ajOa*q-QI$@~c!~UY@3X%r_OR=fYT){YAMZOvNj7%byNx#*@WduNZF;z@H|}uo'
    b'>eW$kR;_5W+a5Y8@@Sxt#A{%_+7TdfiL#i6Trr#S)A*#`VLpOKGmI@5V*SJUz8@ym!}~a*fBx<@;1e41bb9+jo!)z;`Xz#6eDiu^'
    b'7o5kqnJubgO`m!smUv~cK9%D2ES<$8goKe~z8FrT30LVHfX&Gzn68>J^vUynXZcxOuD$!W(vI)6UN5UpO0Mm!z)BdoJ_qZg`k+N1'
    b'9QkonkU!2^eS4oZbf~9|h9|ZI>wEkbwrT7RJJXl>KEH6N{I1m7=A{-rtg(1tn=SFjdxZl3eg}dR7B%v3^Zi9|ZzRst7o<j&u!NFK'
    b'=``1pl8y!hp7y8UxGgDYKKTosj1Fg@3=e2XxpZ$5KOc@uixrIS==EO3xb%wt#cU*U+P^)&M+(7V)+eA{#L=-On`6W9`rG4mv#iQf'
    b'lS=YY^EEZsFjo@`Jh{vU6}EPMH#QV;6Hjz?jFMke@2xH8br~K!1E1cm18Wj(ZrMBCDKzXDzrO7DtW^Z(F1Fcc+ukVxnRyu{_c2&~'
    b'W?+1MA)C#G9;oU?u=ciRbGgr*yKN+Yc5gwLnhd!SV!zIVPZ@e9!}2}++dKSVPhkjUj@vG$Y&`DAZNPjs@v4vOS}1*Z0qCM{A@I&;'
    b'dF0L7jF&!l60w?3)A8Lhq4oTjYVC-=#EW_7bmWf<TH5x)gUO?_b{84>`*Z?~gl6Sjp5f<1v-?N2sOS6Ve<gFtIE>^HGj6vtsycA6'
    b'^00AUPL^4)j9E;>Z;Q0O03Xu)lvd^)w{h~Nfpsf6(st1}pdgBa4b*7t%*oO?UEHme#HBSV-LT2MGy-pR?t1;z1AxdG>}Y~lui3?E'
    b'wa{T-Hif15;x6v1QJKz9Xl;Hn<&bmTL4u5-ES&T?V%<uEmmrb7W%=)H$Hq4Nf7aOabEC}o5eNm?b{g?9%rr;v%D*{FTgyZm(%-*~'
    b'M)Z~*+8upoA$s(Vje7o(QJk-pRww(k##WKOJ>w-;lQZh9syc@ZPYvX<63v^>losz}9oxk32a(w<0k>-SP1PIDM*oY}zZqNz)yKn)'
    b'OyR2~T2Ix(-%5b%rf5QkCm8^FNqK&P&5ZTTi?WhiA)()jJfq}YipUrbFymlx*zDZ6^U?axDmCoZMHXSiu`+nOoB&Q3W+eP#O8qrw'
    b'4g1<b`oktNS-15Sy%G`bwv-1{G=f}3ca&(6?^lsLT5dLr9a_=9ai`cv)3S9pBZ$Yx@pSefdtU3x80vOa2dbNrKsO(6Ze5(t)A^6H'
    b'0ky}u4$PPpDI=90G7QLWbk5f6-ClT|tA<b?4Q>yCvTQWT*R-*Z8j`ZqQn?SBO#+Ygq_z1t3v7^0V*W%5Td{q;)x_3gE4FNb><^B|'
    b'`cIp$X6DeN={#2i8nnJm>isagP~6pLw^CYib*A>Y#?r8U+P9x6u+=uARKML-1^;3TelcbVgasV3Ya%6GgK->8mw}`guVrnuGI|!V'
    b'+Qr<juF`Mp{aMx9(msYGXJ-Q4F5v>?i3A<jXKLr6oNrT3;$g)?;VVZnU{>zE&MSLz(t|qi_;61w;o4k{C=lrAY>(U9j3rK&A#o(C'
    b'=kF-NvBs}2yStw8up0y6JEi>^&Twj4*f)$G&b>|JqRjNWigX{B9#-4SUuP~&VFKQDvb(!A>+~IAD#Puo)pl_%5S;l@8H`VRY}wJ#'
    b'&l?a*jD)zI<fru(?b3`tl@)Y+M=Nx7lw{0wzCNe-bRfpvIH}<z*gBqfb01A_8}xOqoNFCV?LIZlVc-owmi?6q5N{aRS<l9XUi1p*'
    b'`~0$lM-Pf7(6al`ezT7>uwE^0m9+i!GpB;iz>CF67)te&b+kXI&9HX^$HOc#dS5cFNO;t*H@EuZ+-}kUyyMAndIczM;CuO~1?+>#'
    b'W#W1D$6(&WR$gW^<Egm+)hq?LIFjos@&}7O@IHynzSk!vlXHTM1}(U{C!fJ)gDlbP$S2^on<TN?yLG>nc%wM@JZA{>w7+oc>i*2i'
    b'd#?={k`KAPDtBuF$}<{T%=F)#K}cugwxDCQY`>6o{d%}Jc3X{Fs{aFrVx9`XPlJ|;jPVP@+;i%6<NSShWouq`zAnrC^ZB@(Tv9dr'
    b'-p$!}odf_~BhgnvVs$rL*u%|k4gT_n{dpI#(7V~5WDi^D%wb3$c%5+7SRGYEcKvb2FfEstNWY=TI+@NZIK&QT5!yO1i;Z`Ft%Z6='
    b'TYQ2(yB=Y@US4@?;V)`8;{S^$RBLkj_ge(BWv|W7xHY0)mq~oxW=<bc%NEEN0Z=VZlt&7(oH4JTYU_)-LoV$e|EHGm2{qa9gJu5s'
    b'Q?W+3L>6C?X+XuEwZ(Hb6E;rV8xCocVgF>n?_TMCb8yL=?`8D2{8y!NQBRJ9e8WCE>fM_+L=5x30YUGTpBrRM8drGu+@uvSXvSl('
    b'i$Ax18kTUid|hUb+AhQg?xCOA+7u9uQP2A@@d^9Y1eW{b1~ZQD?W{9bF=3a0%g}purI^0d4<rtETVC*$wNZhgJy7C2s-ZJR-RZvG'
    b'z(zfh&Dk{|6|5OFOJn)nh{JiZRi1N8VgyIT3rc*`$}bPFdut|DnjhnhzNj#*4vbtP>tz5Ge{5*YOJ$j1_hph_ud9c<LWw;~Y5PB^'
    b'+8|bcLQUH86RAt@Bd#?&l9_n@|LWl$I!BsoQXenxm&%-@x!(-`w)%`6V-#;(VZU8X89{mrEhCwX1?0YdpL_5JszoqA+haX^R&G9P'
    b'T8HkL{App=YS8`$kL3^k!QjnjG93>NW(eU)XK*l_Nvk`--C<u&w!d`|_wsGL{4PpklSYdE2_z`LG>P(MW8cLqr}{dZrcAxvn~w|d'
    b'g_v^WQ`4!e-Lyq_2eU4^94*Dz7aH|C4xLxNsv4{PY!tLFU`+0&qYGsSzdRe=d0%B@OIl^ay(i7=v-CCFAb`5wsc+js>oeieno0fX'
    b'6aP{IFQ0lIXX)^RukZ#s*gZ|H&o`gdyi>dLa!z8suyF@=^6UKRp7FyF^P1<`52Kpd)jCt?@pIpPuVHX{RQEB1^-*pn*1Q$g3Y(pj'
    b'3T$I1QTq!Z#udx)F<<PoFXdngidX0=e2(S8<76q(#_#6|H*M9K&I5OXw%_!Kjz0g*6*-+j#Nk8N!WjgJXCthbD|jW|hG$EY^VfXr'
    b'!Vj_L&Xk6RQ{pg^EXg^}+63#|Z#@c+#<`7*dZZw%F_jzWh}usIzVD1uLL~iyX*KKhfA?0zy>I9F?G5}a^npg{x$Jp*wK!}_I~nWE'
    b'_n-=$uh)?-OVahimsjV8L+9)O(G?AZTX^Gf->xoIZezehb8>Jdp8h9uShw>CpDlY*Le4|$w-2qP2W^*s2mEom16_>n#XjQZmuvU2'
    b'F000wOnB|~HU^tTJ}H)W^~|-8V`fhwf^2VN*z`A}!@|}N5!3t<NN`(%`FDKo9@w1Si~u_1@)7mx3%HsDmBwJ>sK-Kdwlk4qZo)C('
    b'17VwaS-T;hAB53-J)Wh?!Zt6?Zf3{*)rjxi{j<{xb(9;l(c0es<4q~*=cG3s0@=-w{>VVXODCNN#Q!|syqsdItOv;^wzdP{oGQ!5'
    b'Jf-l-DUIH}?!2kvE{3`<1A{;97^<V))Z~!|x4BlzNNus*Ug}L(4;{7yW1{3AI+8S4Pxs&jk4yY_qFB8C^DFOrR8sDGydU?SMo+$P'
    b'{}?=UMcYp6Tn86M{ZDM&0(*HwB3Auo)SbK{gXf@Lk74Ztl=t7BtA**|uomR`nUbG%h%AMZGia@{V+W_}%ltC>^{B33t1in$Qb+F+'
    b'>x)^}0$bHyo6wf8<FY&+eEbz3Pq5H#^+Wa^Af{@U=XMuK9uh|n!Y?$m#@{7=gk6FDKn<DJoAVQiU--f12!~DcR9XJ|q<p}M{UkG_'
    b'B02x*qk#q$or<zXj}61Et*`m|n+Vv>6u271%7iuHs+;Mfm6MHSGEbeh;#5z_a(orLBa)Ulwn;QKcayfsP@qSkQjEO)^fw=yd@7~r'
    b'ygJ_q**(uj)6t$rU)QD156W1hWMSe8$m-qAZVxKeT2vMB>2%!V=vWB{Mh}?4s*OEo^oeNdnI|o4c4OKPQF~TE{C`YcThn@O8~rRM'
    b'nPi$NBqmWQyOIcP4k%I4Mk3Mfv%k;(q~Ck~%u{mT>ssqt*9O-R4b!!G?Z>11xVeHr0{bozjAodZS=+57<^yw*Xu5JiF!VD+6-s=I'
    b'Rr?#XAIi$#_u+lk<o3nDYK7f~uHnt&T;A1cd-B;%5R>d^w~;4xPAWtN)sOUVmqf1Rr@SxU#uvS0+w3~-KFf#C@N<p&r-9n=q}5S{'
    b'x;U_FS2`@|3H2zNHKGoODq7>Y;*b0Bi8;^4irFtg?eR_7CygMV0fUy(%)#qm!_<Gj;eEa$`gm7yS?y>^RPIWD_gQwvQofwCO;lbI'
    b'3(q0w5j(ZmPEm)I`nE2O(RD4{(Nz)q99M;;H|NN%(KnZ8ihPNK+SRxvf(WFi-Hbl#gI_M?VU2H^b)W3sG!;wLpkj*Ez1O_%Z&CC>'
    b'qN!gwy!ty}$h57^wc7qXj{Pr3YWN;2p2MojO`eaHG1eA(cg~4R9>u*D-}$2lhb*Z*Dgpn!PJeyA41O10qbAEf)b|yqsmoTtN>2N7'
    b'08ZD}Ld&n|bGmq)XO9ip8z!@%st#T^txxbvZQHNMt>K_L!@XIvT`Id^aFNe%$%(8lwy$IJw2SWsM(LM7luyUbIxn|QM%9e1x}p_)'
    b'GncNlX=4{&=f}<t?2p@@%Iydmi6ky>-Iv;eO$rHhZt5NCZDnJ<_;0VpRLy?2W#`&>vQu~ocwhDd@cKS(C+}YmICHlwF)n!4YTqJM'
    b'de=vvhTCnPd+xT8mnz%-o1PBWa2<5UMsxk&vbM%hnvHP;dEoW6vA<?%Y6Hhk(~ny95!F5L74vayclJuSo@>tY+bn**c{Jdj4P!7m'
    b'U+wD9^h$$<`)q0HquWPE=zQVHL$^u+D^$Lm0~{KN{e~NfCfyw)iMCk`p8Sjmx%G(b>Cp~+;rs{~b_X{_S-oJCdHM#tEd6Hq$1}E~'
    b'moWw0vJqaL-wS{)?rbu>vlC~=bUZ21y%nI4#}CtG7SgrMPQ70F(pLY@?yjpAqrN|l8eTV4mHj{;?61Q^qBAZD7t59<LXZH6Kkd-d'
    b'qW*AXCawy^#$5ufmXL-!*y__a%&V2-Qb(q&5G1!tR~Q%&NKO6%chz^a{`td?3v53Bdu2_>M??8hDnGedV^@1Npg6XhY$a&K)5G(p'
    b'm!AbpC5WPG{hHZL`d8IWro!01+=^qh<x?5HcPaR|-PM8D$hwS$DR+WS@7J|fTjcwmBzi*r&e^bYI#|bA^UzzL6tkGsD!mX-;?L#`'
    b'+tkmy866gT*j*l5fh(fJ5_k-e$-_^Z)l3i0_h$X9%98fjyzW`l4r}Yu=G_`NW^=g(c7X4kYEr^|5Wzg9>%O$k=VGbWx8U--Pki1)'
    b'n^_(@HS)LXSs~Z)bnOSvdMlpZ_ueE&9w{)d@#b+?V9Q)zEDUQsuWiM~xFH4N>5N6l`iMN|os`q(0(8Wu-Hp1Z)%1oouUSx%jm(YZ'
    b'he2%mtMuuT;4h{m?srYzwjZ}6%t}BtBAvso%+}npQ8{^Etp*a*I{6gH;OKqJMP+)moYVCp45U*DzFz1Nmtmm5BaJ%K0I~1;ti{E='
    b'll|S%<Ga;6i`}T;e={V>KtEZOHkK`USZ2k`#a7lU?mkwc<3aO@O)W(7Ax1bFz9lUSz3*K3F+(`ptj#u7dV<SA8o))HY=Yd%8GqCe'
    b'S4~^ol!6=$##Py7Cx_q6Pk6WX!GH`)DbQEF4cVF<4yE<`I-bY+j#wsJc?*RDd}+=gLMAJN-X;p?@JY^U>AZ4xAKwE7a7KeaRm42@'
    b'dyfn9+6N2CjH-Sc#tJsCgTI*K7}qRWRma29{5<|c0Ik+Lz_&(zvwJCaupMN0UG<}TW5N&0+UueAq4S;Ymf35QHOtCoTA~I|?%;cv'
    b'sO<Nf;iPIXQ;D*iv;n`vE3tJ?;V&<0XbqnXZ!d}|s?9~&A&H)U(q0?&6c|J#s^l?JZtvT=zwpRe+xV32dUFp-o(t$rSC*`z1TlB_'
    b'!gFoYwZ)-5neS_YphBISz?EhmyB*zsy%ke<S(um!3g|ttJALW91p7VvoK(t0Wi)Q8+}^>w>!r!&XqVYP&St6m`UERKFmAD^HaTB%'
    b'ZRaE%&U$Ojh{$%n=Hxf}P{fZ99}Ng+Tl$ZSI<eCmE-<89&MO~e@$w4SPWbP!MsM0YK6zH9>v)jnb_D+^bmRJ{l+>19riC`LiMgaP'
    b'>yQ2zlOThyjM(>BY4p&;t|2!z#Z?jAaZljy@Q-5$Z%-&ZD36~iryL`EPSOO0+yU9}cI&gy`@Xjs>eiE1751D%+=N4Dgav;DXTe6!'
    b'W)4-%yQt_m#}x&=$AV(8>bGovPM;_4VD2hD*025e;q*A$uNih{6{hMvOR}`O@k#NP68G=j-?i9H8=?AwUAI)mYs&3-Y~BWcaP5`s'
    b'D|pvjKfKABpNYuyRKDGW)Ro3LWr&^mA+rVXT8*x*_j@k0=1gDqwsM;LHoEkwswQ1K1;3cR#xwlk70#@AUZUkq&lcy@f!_h}AJfv$'
    b'(SCM&>NRb?3yL-G3bt5nwD&9MtsTLIdLygo@YsPg!G`_CZ&uZQYT~YUYT~de4N@qXAo=T$PSoAyU2+`;X&&oZlZaN!N1K|jy9?Y('
    b'>h+~dMmu?N=TG!*@(l&BCf5GY^T<}o9Z|b&FHcRkT8v#PBkscf<;;=f%`}^(+npp`JRc*=#QWxPecmAJqb(oO0unynmo6Wlh)R_*'
    b'^7Z6$qFf|;6r91QqlNVl-^Kj+TAZ(s@fR~MCm=k=L^kJ6>*nWZCW-vxQCnTHT2oiQ_4PJ^n6L6c?btSopva}N$XB?jBGs28oc3hn'
    b'+Z3Hng<Z{=>dwesq<=|_aK)|Kes%Cz*4oS6YT<3)%{a-#o3cvIL2ptrTkGFlUc7+O3BbK`Rb9v*S?g@3l+R3!QF*X^3*fGuPMOQ3'
    b'QhA28?-XhN3HF@Ap=`$5;`c&<Sv(v0uAGV-8ZaXB+2AGn&aeb*pBzb9B)0vge;CC=B;UNsQFCl&`E@1f;HW(ej+c`=y4SGuauW_B'
    b'kVG}I2O96Kcf~_e!6_832i$wt3V8oID#h|medX9gU1R7u;zk<0%olnAHCtp+%`d;4Ud?LBoqCS6O;hu#(q;||>}*YafZghPyBZ@j'
    b'vs(>>!0^9Q(^(#T9+;=4j677yKDJpOE4AlF902g_Pf~8BcegDsvX*XA{b5TE&NZk=C&aIwZ8YsYhn>-a;YO0S9hLy4tDF1_ig%6@'
    b'a=U!2(NTHuT|I7_=b>dC#Oabs%AHy#>Z-Vb0Wc&qlWkf$Eo+Zwu4~4LcZ&$m=p$1K2c@Si20z|wTgTy9TS-Gl(9~mf3nimZmB~s$'
    b'p)iqm*07DWh6m=G2L<+RnmoQ|RIu`008^ZA!ZV=8w)U$jJa+nmciluSqhY-W_Mo(p9U3)<ri6$;?O^Q~WHrZu=+5k)+Sc#(qaJA-'
    b'PE3C9l2>`V8^ivo%*?XgqcMw)d4E!z4xDPI#r!#KLfz-{xX#Z*Zg(v;*H3%ixQ})Tu)F2CJ!eatlbYjSZ#yPklNbGUf}lMp*2JH{'
    b'Q1>_KN%KJ5Mqu_l9KE?Cxh}W|em%nwQbV#nKtFs(u*2DYhc%8v!Z=T~mEr263rp2M@z&fcw<PU3JW4RmEBy64Fu^LU3@jojp6<~R'
    b'(YAob%Wh|7c({3PpDf^T-o3lGdQs2pX~-OQ6G5CzUiC>;_LJs8$KTE79yXhY-J@usJ~YIKBpq)Q@QYy@?F|kF`txC#Fh|>G%&iYz'
    b'*YBieI+Bq(>4ID(rI}R67EgcFJeNj|Ise7@^{CtGr^A`zQ$pU5HOOb1K2!}N<HS|Yc5N=Kjjjfr%y9-4MgP1nxODmc;rw}iE%$nP'
    b'`h?`>Tv5@==k{#*gKTo1bOkA|JAoHzAQW6XIKoC1)mDY;tl!h=)~UrePDQz}L1w&Z(|6`hQ6@wKr*o_<%7QF2v-EY@qQWm971O%|'
    b'39777X!LL&$$#qgu%+TbyYaf>KnK<suq>6(kD9OVmny!k!T;5|hKp%x%%ov$!$`!Z&za2yW{<!(iv%07#9kb4sou(DiGs!p<>%e3'
    b'rQzq+-0TMxek5N$3n>&YHz2ki!K8IUww=vqi^`{FBAqEEJ!M|7b-x4bVy})5;ZHfY2Y*a>L6n4WMfd!7ztw^KnO?$rn~4uY>`nB>'
    b'_a7Hk?I&MfPPzFF+D}gXr)RCwV*1D3G$kMgBfsbcPutnM%VpS$Z!%TN;-rGC?KJCMw_<>jjrDB2?2RL^*@~U?4+@t%_UU~8kng_4'
    b'(pKH5{(8-tL`vA_P5A2Fy>}%%eJh7%&+7G*5W|^nrz&{&?)VnQXNj=@5Y67>SHFHvC-A4{SD9TydrAP~#TRC?SQcB$7RHx-Z184e'
    b't>n+GRRiGiuRjH0=oLSPT=Nfd<XIhTSVw%kdqxNJ1GFP|SO(<feyi_Z_2;*;61?pdL9cqQ2{Il~5xbPyQiyAsyy>#_Y4?(kDa8Da'
    b'^>1HE{d{ol_V~e1e+Aoa88S*uY+@FnrW{<~vU^l}al;x}HYD11>yQ6l-nC=z+Fl?FgxKhjyT0GX8g<`1Tj8zTW;@Yr&pU_5KD|x3'
    b'2rvzIBh-f}atXfyER}v|p6V>v96|ajq;`S;3Xuqf*QylorvPZTDtqaEJX0Bib*)Z+)5`XZL$3#nmCMcumh2bum+3+}p;Ki2R((I?'
    b'9>sSH1mY9Mp)+p4&~w<|*Z+ChQpGD%<a0+gYoey}boOx6S0TYK4S~D+@+39Cei%u>)sELOp{>~E43$z(BZo&uslx@+>fQ+IPZN!;'
    b'y3>zhWY~Frx6HafsGhInd-(kIJVI7#1Wl}i0#7I1Lz`JVb;^F*Z>dbkp|9S@-@p}&N96F0-Ec$QWzmH^oKY|AjK&H(wWH=~{K*zs'
    b'Wpq#L^bKe8EX($Tv|g`7d+@Rk{>}Wnzu%RYT_3sS;8hP%wkYAaJU|i#f>f<5#wVIPe|9QBk=kA;^o}!}h_4thm(=tuVc0C^TEwx3'
    b'#)ftSE0X@8<*;v@(p?TTTxaMZT}1kM0r(~;A1hgjZ#B-hqIAc<#eV1V<4C~Po({gttHp2?pL*`VKqA)$H%cRQ$@}QpV#<d%#FlFx'
    b'N<Uxs!?Au<tg{BJca~VQYw*B`^Yr3`Pve(M`3v|n=vl4ayV-el^Xt(%?PxhicFy85B~a;ZCTmVn!*Oq0EzCt_(ZU0ZeH%+lQTJ6x'
    b'tv63@YyAonk!81h?WwUVu~#f;v!nQ?Cd!!F|J85gEg|!P*Q}k@gkvFx7GXTDb9J7OoZ~K->E?4VmyJr9;V4l!_-ckZtNOc^!l@VP'
    b'mGIS>em_M5?_?-<RF63xC|+S%j0ldyx)0M?w}+O0J}i--2-w%h;B~j_J(we@o{E`B_9_sdxGvQj@g)yEN|VxiI`Ayv0m!`}_}O$8'
    b'0U?&Iti#&9hG(hG{WHf-<Mw`XB>flLK>Bo_7^atE`TcoqR-A(Ssh=MnUWW7Gd0`L2hf_yt={mk})&dv|z|klsE~D<}J2muvvD(x+'
    b'm)NMGFaKbPO{QD!vD4lD*y~shsOVTv>SQE@HJ<`pil7ke|IXo}I_oX9D_c>H<%<7VpXZh8xzu_Jjq#Y6ZybWxbC*~Sgz|RKab^Q('
    b'P~OwTyjCT{&Llc?+-@!8=QVNTT!!#~9}lG!JG9ZyGfDnrMyJ1ZFF!uNqV;8qfo5KRrj)8&K5N?dmM8Irv)}d@Lt%)8{+^6#{bR=j'
    b'ZBRsMwv;;n7^C&E_-en4>(WNKwA~KUOTT;lJpTT_?uBpOyAoY--wyWhug7ORV6z!mSKHw0w8i52g$x(CQZdSTM!K(?nUCJ#9>i(n'
    b'vxa<?yq0zu5YpPUpM0~$DN-|_{%WO$>?HfmT(7zibi+&R+_^2K>pLr7F_HP@ZIZ!)L5exW3JbAPYfCZ)J|A8FMBVR=cCXu9(8-?J'
    b'`gqPo9Z-<UZ8Yx9W=c|h&2FvHAK&*Rx9xQiW;<dgQ+(5Z-#-n<<2%%*R6Tr6l0yI0+_LY=eO;Zm5?Ch=ta~~-v&wFWR6Ffm*G3L}'
    b'Z(3ZD6~`HkI{v`x&{O9B{@iWQsRq)6q`M^a;cL>0KbObt*w;JY1k@Jc)s;nau<jopboA??qkLzHtcn2DNv_$YsX+_iG$Ea9qjko;'
    b'c~;S_`Mb1j7ag9j6f@#bqq(v8&EJ(-r&Uo0@U7X4H{EZD8(Fb255#9!P8UH6iQW(qaCFymesS5Ec!<<nZ0{#%D=%fG<82C)sIKOJ'
    b'KT;1Wo2!QkB0aYt2Ob7g$@Q3C&aUM)uhtI3+SOlb=Syw`|FsCu&ZF7NZ$sXif{2xHJjnb0RGfajUv8QGqb%3nlQ;)rFFKy?=G92{'
    b'L6uOW(sQjKlVbgdoYn$o^spj2Lj4K*#`x_x>2TSuX6suiCtl!eU*+cRd~MfP;-VGI11AX{2>I<c4^wRX>#e};$$;x`Q~zwckCRDv'
    b'OJRqh*PUKAb*EJvDAz*+4tCuN(3@&T^L<^mmV578tm<U{NIdm9IpnzHkRP6`y`|5|!UfEQ_gU<4gUEubbE_CX+!*j54Z?flrC`;v'
    b'a5c=kM<3k9aOpvnS|+8MPh!?vH012@9kea01E0cl<AF-=s$Qy1x-By3-?4COL!UYq<6?Gjj^jGI`BL*TrcrfebesHiW!V@{m(lLc'
    b'P%q?x20Jg(zomzJ2GB1%ZDs3hjk02IvQ!NuA2n^oF1w@U^@tDfQqtS+yI|u6t*Px2Se3VPkuszX;#wO}%SobIJ`FM`b$=WHGSJYR'
    b'vy)-R_i58MAVoNr-SfU#VG1g_?!pRXeH#0>t$@jG{Z5vp3vld<*IB7A6z5rtjqD<0h<R@gdD7}F-z&{}k1NNUqq>FiY=2UEzn+nW'
    b'J``g4D2fMd|N6X`wtjeZpOTH{X!c;`V30`_>`!oFLOoKqh+Ca=WLopQkl)5r`<czE6+{`&kV>r?3^B$~<GQ3nOZZ#%F-60-{m0|i'
    b'%Q=2A(?eD);haW!6fSy=-bOey$rF5kFDoU%8JgOT|8FSd)(jW(GffQp__GysESaxR3@}T2I?kLaAR?P)l24YGCp8;7G(OYlcf~@t'
    b'(dAcrFy|@JqYrr6+zz=5Av(Lp9OL=Cyv0WBlny7IXJvZ19<^EDq}XZtG)t4AL!Ktlbxotw2fC^|ETqd9yJ}rZ--BM64ZR1`*`P0*'
    b'_UXlYqW)@ANhQ~+`Z-><O5LPWAqT=AKYKl~JvzAW+ov+8%3arLY?tko>8F>vr1n~4x_vQ4_0d|Duf|e@j_Wl+*zhRXO4%yu52J;>'
    b'M_5W8L^pCu>A!k5TN!ibO)ARfCLBvws-5J^M0$R|<$fM%?3T0MPlOZ9MoFe;p1qdaE{;t6)uhdn3Rc~V(*~R}M1$+r-_mFrExuAU'
    b'1QI&D<M24E22kVpdtc3rgS#GGUm=B7sQP$UI_O#DImKFX2$r+X>Y3gDsMSZf@-z9km9tacHp+wL*;n1Vy{I!b0NmduHgVsVUUyLS'
    b'?iXZKc3rDrT(*Y)>4Dkrv*u<wo@~JT{F*h2%3=B0%&GrY@HmerD>)Ha-<2=tTff|>H1UDsM%AvUBv-p4+`w_z_j}{!b+MtH{<qyI'
    b'tHG+ZJ~xE3hx*kutem%{wz&p=9{s)$i?dSMPa!@fZ*yE^@X>7cwj}1QXzM`B%LCBJ-T_&eS6wIU#E*fhtdiIDv?}#e>VdSn^=Lkg'
    b'K_Gq|eCMk8^!8KXbyef4J0&PTuzz(92kl(yG?+;uCf>sAEJwQ{9O9M4{5$HnKtNM!AALuC@;dAcqJr+`7uxvK|CGIO2~_>!z8LS|'
    b'_IT%;3mpIO+1cTHC!5&;s-Sl!h`zLTzdUx8m-W$}UwQMwn0~}z&>Oou<nwtzJ!0lm3k)1k@eo4e>th(Wd^)^AGC1*+HYanJ_BjN5'
    b'KIw1o(y>i=L(n0bi(8iq%1%(-^5L8ly|nlHtg}^JsiGXBpKVNz7F&s9)9}+>>2<0H(Iueyhq3D%U6i@6F}}1~?=FUZiaE*LL9nU5'
    b'*K8HlM4&Wc4n0zt_)1!{Me&;5eZIW`^{9aW_h0VIN1xHG$j7I_n5`nOvFQw(Df^feg7LU#QF9lV(7IGr189Ih{pl>8R6M)}@op*Y'
    b'yGH?J%UU$)4@)o?uHMKtQ@M>vWl(u{D<M7SUR&+4pVliOXH?Y60=9)Fw#CnZ58fNTTMNgBY9kvF_r-BJ9-4@`jIze@@14F@yR54C'
    b'ZaZsM8}o8EUd6R|amYsbga59GyVnq&^zwC^n2mxUebH+CcC|p~1?JpeO?6pmmaa~lpsux(Q7=rq6WQ+TIM{qZ>|Oq(O&2}|-Z%0|'
    b'4_h0+TsCj)o$)@&E35{$7herhpjVT!-g<o?H`4ggp*uVg((JkV!>HZnflsW~#OjX@i^WXr?)n8XO3dEt+p<s#T>5{|gd7^5N3#P9'
    b'M4eXf%w3Qz<%y9%&JkV0_S?I1M~uPsczx7CwPuW((`giWW!2vIx!bRo6G@Xl?nj^CjoNBxMW3r8YLm&1nHf?wU@=n4l=ZcP2Q`E`'
    b'47|Rmnv8|>xk@&Bi^s6rc<ZYv7@?&3V5@QOF)pyg|611@>^u_oY^DK@|8fpYN|Rg5(WYsI0`G&Yeqt}C5vALKENx6(Af$PeTsB~{'
    b'zs(P=P3f50Rrx(-v$*DqVRsSPqYG^f{E**)%e{@13q0|*YI)vZ?ZKc_IhQX#emEKp_E7n7lY0j`qCNd|(67xgT^~uD^Ds>wR2;IR'
    b'-Y2kW7OB(uB4mrvz(X|1u0ywLm**LC#HR){e*}Z4RV^9#czh1pH{m>ItT8iAy1k!<?S{SOc9j4mjZa`OV`-gRs`WqJ*c!aWkBrsH'
    b'rhDfmflAnlbW%A5d`if-KI3Hfx)Ihb2FXHiJ*stK0`g9;H49<Yr-eyq`-IIe8?DfdU(fy@S7{bYZ@%`+MG7Ity55^DCfIg*^5*cL'
    b'K)u{fd4IF+ljCcoFVamZag@FfrRBCZJ`Vs_Yo*v|dGp}(GxRQ64c(>5=DC}SBn(_UM)qR~{a26uw%qcrGRu&aalGW7tW@Q%TO|hx'
    b'|30j6_D}7trwePRZl^-J=vtLd4|C3@=Co(yHud`O;zDBY9cqNn?uP_E+&e7{T%HzWj8Zo;f3n>l7d7Ip_R##!3vdVC+1^l8d4t?u'
    b')Ovzdp559DX`TOA(duF-mv&@Uo*v%CC~%55jsbhCe{U)M+6=Wh>0B2JovGM;yCfjSei1%3xTAyTwA=Xkurhsn=JuzNm4ptqnYquj'
    b'M#^}1CAF}Q`|cgIRViY=mrI33bl5T;0`PdjXC?@TfVlw*X74D{=G2O(#-~FrE#2Kf5LkMQlh={%(T!mfKmKO3jCA*j75LTfAIh)>'
    b'+cu`rGjy;!wf*rCfJTSElhj>grzyO$R~@8&*|^=3ewcm0W6O&*PqM1tC1*ZAzDwM~aBy+uyXVaTx}RfO``g6&-Vf(jrxCpdH!q)@'
    b'>XnO=C|PjOg_Rl7hjs^BO>n_xUHn!*j;fW_sWU-ao5NF%srd8<tm&+0y_VJ38281)u8a4JwD|Zw6J+=JVkH@>=-qDZmowMyJ#D?c'
    b'M{a3JTwcq~#(a-ez3zC)3LfP|P~-*)%-V5=IrDB%3rBz4Ejz_2dGx6BZP(@G-GIsFTw5skRGw|hUdE-v$%L7b*nzLhqI~-KU#mbS'
    b'eJ|{Yv)A&S83%8=J>O0Xv^PJmn7KQe{gJv=Zzn$B&an?eEp9ohd{N!>Ull06FBB{@1|k++yX(9=dL)5r8zur3(@!#cwwv#>VG+MG'
    b'FYCKY2_gt_QkbtLIs^mgDU=tYf5LhTXT3q!-jF6=;ba0=nyjZH#&I*9E26`7YctrG5ai{mted@3|8$-oRr6@uY-yYws@bMQHa0%t'
    b'KRf^CrQE+-p1ekqv%KEG1QpA~l-b*vZ?M36eLlAb_<AqGQEjOp>abOu@TB`$7^#05KgSF1o&*3vfz`Y6B!uMUoy3h|FH7-vD?Av3'
    b'W{u13mya5}H_>IkS9<Dj!ohyUola@CG4$C-o`Z3g;m0Oog=-=j?;LXy-BX&&nd*mGhg(x$UN+$XvHot2U!&SfLs3I-lD^f_y`(KV'
    b'r#Vv>>l^h~a~mwei*_lH^*Tn8W!Q)T;OjR(?<!U$Lh{<+h^ehlN~Id^y>zP44cg->7L<Wrk8&1xm0O2HVPm?T_kR=iPmA^3<w(c^'
    b'#S*@xJMqgN66Wu0@SGT{fmrMPY4g?@u8|LDc<a;ZR>Ij&d6*T8B$OwIuX-I{h!%hh9#<6y8`VEDFhu5W$6v(W%;1*8i)-x$(ge>Y'
    b'2W{4XqZYh+RNkD5yFZU(JAQ+eYHwAtC#w+~9tD{^v=<-1v@1=``HLNW7TdBJ>R93q9PcDl;`y;>KEJ-)>rK0acU8vNsaX<$7G6vQ'
    b'lj6LKx*EvhrpSD?d3tx<A0C<{Ts@QmT3#jR4tZ>aFS-@FJoFm;5m@%dtt;BC!s%x0nY%sS?MPeo(zJ&3*KfZ&--TISZR{u1AhBK4'
    b'wT*NSUkA{-`r@A0<tS@d^oF$GtYEk~E(b*~eOLTlzEv~eF4dIlE$o*c!w<#RZinWr{%Xru@Z81zcnkkw6fuzDhiWYY8X>oC{4}qB'
    b'7u3wH{40FxlNUEL3?A{Je8-IS7eD{)K@d`~9A`#SH7e70x4qVDP3`K3!`BVbHpi`Z3*W8cey)UeNX5r)Yc9nH#iYF51lr8Wikabt'
    b'qNBANY%Wr#ezevzfoqg7b$Kd3I-4ph(Auw0>T((k+GA>42V;Y`(RsPCY&o8uDDrv^bS><(WSsmtxyjR;tp>eY?M606M2ns8<Q#;I'
    b'#=XDRI=cjdgV%PD>N%}oyeSz9((bNr2R0lvIzL|z41)f3vx+9vVlUkAmRAs(9)c~zrwU*y%}<k(l&s@`h=HCn+=Y-?ER2uS4SjLn'
    b'i$VNS5)X4vesY3D0NX>kKG<~!ObiE#ych9S&{hBKH6xJ!cuDEKn>KnDtQioqD8qS&>O4v*(cPf}$LH7M!fZ!1Y(S1+@UlHL5|D}p'
    b'th20sC0G^v(|&Egs!`}u-rp9n%3Xrz9>$os&lxlR)BMfg()425e&VfNb?W(pwb0|(yv7_=)l!aLMm|veez)8mU7a-~0A8+VO7bbJ'
    b'V=kPqKg80LVq)>ao4r1srB>|hxVCNN=9ZkP#Hg`L`Y!yu{PY(EiVN{XuNrCBX<wz5l?(S7apq<_;MpN59y<5!EQlYJ@)vpWi#5R8'
    b'lZ9ScF4LLRs(0$(r68e1KV<Ja`0dB}rc9>f-*;m!^N(rqqx!*~{Pr)eYtBQFy8ZqnMG|a@p;A6Zq}ec?mH$ZcAwCY{xu&`=@MQGw'
    b'M7=Bz+;}p%s;yH62-CYhOMLun9ps1}Ss-yW-pME~o7e$GGrJ1bWnKQwGrtSNrIhsNuTRg-wb7!<(iu%v=8@{uvrcOw0o}zs7dg49'
    b')`X?UEe0Fdm}`}HiPwomp*>Gx3%w2$y@Fi@wNhVj5=hjbFLZfvBXg6#2dCfesw<`%L;H%09oQUw+eqFuZyZm|BkyE|Mb-B|v*sbo'
    b'3zZ`(Lu)I;f%Ag<xqN_2*%0mTQ=&o?!#0_A)n#8SZ%eIhffwIPBB0)fUQV{-`|r%p>!r+g2Zr(V)aejGFp9ueo#?HSq`FYo2wvBX'
    b'1Bx(gGQuXS#hKIyg7HB)a%UpdOPg(F4Sr@g^JpH<6LeE8#+5f4Nk@F;^uHF>H+=TT=Ube4l>h^eKIIdON*gLid@~+DdD46nk8(-0'
    b'+0=<U3RTh4K*#V>m@D+)BiozA3Bu>~I+Pl%*l%C->$oK$v=uW~PdpFP$7;0)@Qz!Nf7mPVE2F5F-`g?;$~R!pTV21X5$GugRu`u~'
    b'87n&FccbEpU&Om~m!*DXE^dzU61$k+9g#$9i$=~M{shRK-;mY^qu#7jttt>ZWb-Cz7s<T*`j<WOLnzK<<EiBSo1Tx<G71@Wx~@YW'
    b'&}v=i74KDV<8wkLsK;`#-pgO8jT+t+*&mYQ*X;(^&15vB6S2|eb=OvfF&QzW;|phIu*XcIG5OVsR1A%M1~+m@n;*rl*(p$p%9UXB'
    b'osC99y^Dg_v7)i}hE-RKl>xs4;2fVy=;n%&wWJSNJ^j(8g)JR_;o}XM#S0UsONh$~YJ%~1lx%*W-#pmpn3wc`(&T4Vom5F-n1Fh%'
    b'y<E2-e}fxyyV#7*`{{}YS{t;i4B89<#tAC>m2zCW!||pGZ^F;L%GI(%WjUUXp9<D=+0BI^>2!TXYIth?YKg7TwCH<t<}LiKNtB8c'
    b't51c}rUFqYlU890OGfoS8B<%XxXFIBcwxB;j^1b$)<)Oaau6*npgHRm)vQOL11{2h7YPADDRCNd9#y$moNB*%(b*lDHxK62@VBvN'
    b'<#kB>DnN(5GS~P`gHs!QqKbh#BLZ|PQrjJU=#0|$Nhh7@dcl%WwE7b{OK$V3^?J*wwqK4r;9+~Hw*^`v<CN*wdcXUXjsd}_r*)~Z'
    b'UXjDgx%8}Gt9N`+D>d(btV!QlcG9zk&&MB9HJyW}zSOn_v?0ghiy>m0w>%l3)9F#AOQWXUX?w{w;ikK1eO2@soj=xy>Mxg4LjgHr'
    b'3q{=8befrS`XM=E+!XG64&_VGau#pqqjZKx<!*nM<oF%%8WiK4MBF3U=ar@K>~I{jOjy&l%IW1UD`)EI5(|ALHx}UIt|-l)Pc&^$'
    b'_TQfF3|wni{vOI#XmX{^+<AkeVlAua{l87xyuX{DcYjEHV;>eu^2rVYDsvlj`;v7*x$lUey*`@{!2^=)9npd#XA(sA{yLpO!RL1l'
    b'w<f5*j4H7|0_=Vacam1cG-U5mEsP6w?!yn0+kbW}{j4r0xqEV(Xf5rB2*jzXutt{m-g;}^3F#1VwMtrF79tf73zEy`nE&9^kCG<9'
    b'kM|OElryeml&-5X9;A40wio4Ac>y#Pvbhm#_|cqxB3fyW0%Hg)7uz;|jfe;4VZyeoQ|83hq7`>CDPTV@xs&B7NY;bF*oiT<uMtJ('
    b'Q#<|iS82s}b&oOcvO89kGyABr6znYM)ucqxrK+(J@jTHig7;s|_3&1uB5XpKIbTJMHy;GL=pO1&MsuAD*lIt{;u8f6WM(NX_S&(E'
    b')}C;xzvr5MTi%FMVWcmemNx&|<JpH_3B@iLmH^{<l41%SG{dWVTf*h_uD{qncI^(oEQ5iBEzj-Cgri0iuV{zpWTO)ET7Qg*{FI+Z'
    b'jNJMQ+UJ}4^I>~~?$)o#rF(O*eR)TN_C@E9y5_AkguT9J^p;<G=-#fUSwrP3HrnvIKw~*F<8`K-lf5!QMf1(ycD9aUpWZSg-$QcM'
    b'(329X_21fZ`X<z0u5$Z2uTAyg@1KtVImS~owl}qwOmNRqLG)kEc^A6_HSE!Qi=R0#d(HUKZFZo>;+b5I&)2bke~=sYv~D-|3xM;v'
    b'smplDeM6j`cdsMN?|A$D^8$P|Aokl6=5W;xG`P>g1~j6EujyyfUpoY&ri(+-j=#~BHCtoo{np^w8o>&MMNQ<t8L5gmNfNk7dUPnw'
    b'Lo=-H_UC@HqQ_mt5h~KeubkxHtYF_Pf6I3dKOp0d(A&tR=xaC6*^&Gb)ky<nUf+9k`V6vtzcUoY!tEm_Q+>$!-#Hq_o0XO&W*!w1'
    b'5b~~uAxxNQSr&3&P8_P&BOWz}>2L3?nAxowM7SK@z_R{+{9$7`)!~s)&71y~28(pgi8n%(p(V4QKS{a}2W`KDLC6dIBPsHr(`$`&'
    b'aA8$)=1n6$3j5dO%Ibj0cGfRz^(T&g`3>_jdQRy(`u8eTGCb$#pQ@8=1wOypQQaFo2(^Cd;j;eli?!Ru$91U{G%G!_D%A4JXrkxN'
    b'Ltd8o3E2c^7rsoFNMe2kz``I0O)db$*PoR5#pT|tj&@Gdfv{W7-a-w2ey&=Yi{N%#;u@4vfIQ2eZXQSu{%h@(>zv`MgAdle*lZV3'
    b'Pb0iFv;ShK3-8WtI!ZTt@yKbXLgP2Lo-5znJNV<hSmhf$UzPo+5br5--bCpG^8JRfEw-msi)lQPyQtLq)v`umrN6JR*pAz2=Qf$0'
    b'=*bXjx4I_L?^cafK%Qykb#WlXxwe(C*bAJOAy`Si@xK|84jm5uLN{o^Q{b_mlscUfXQB#SP#aHZzQz@>#uJtR&kAzm*!U4ewsP4E'
    b'UJMD*kLB|2c-js*m`#|v)GJxgedOO2y9U&|*i&1H{>WCD@~>a-2{cy)JX}qYogmobWmp?BEcUhzAE>|gTN9Zp8Z%(uU<a#pFCI-Q'
    b'VHv(iHPB+#XWh5&c-+F7KB|px%Q0bZ4}F|iZzhmF?~g6RxtG7cnhMpit4?cb#STIqlZ-K<gsKxpLPdX(P&AeH1*OAdcNDpg>m|B-'
    b'ZaK!%eLur%lkc-JlB^Cv(tW`m0y$canvA2?qx?K=i3|L;*UN5t`G*@Lsz4{Trh}uaF`M4|8a3`ymo#cM4z73`^o&IVlX+@qeZMdu'
    b'E?VyFRNHa{vV|LmGvy&tX=zEVn(^FYmCE$?$(0q_lM!?;HY0wiG~QBZ{PTPlMYy}%PaOcxyV7(q_9DujmMU|i)BynBGbix;+Kg7m'
    b'c9Jl=&UZj26`5u$lTTdEH$HDyldcqgRQkR(bTW=dj!jI(4O1DN<_*bObl_jlzR5)dYsgD2^wcqovoCs(*%L;0wQ~Z;%pG|0J>q1Q'
    b'>DXEfS(HH@?c!K{rE_UjTkN+4{wFAeZ|#CItE+vRveIpEsR?{tKKdhZ&&IIv`Q>0QMw#Vq*g7R&qdk0>PJq55<)m*Dh4_ZKson(Q'
    b'Yrc1y!*`HJ@DRqjd4*{XZx3e^uBom@y=FJ2+^g?&C^UxPh_TtZ7ZkJuL5<aB1S*|>*b8QZovBt=@=U#*a!V1>1N+H{R_on!ik*G%'
    b'O^I$t+=e^s8|}~QIQJ+kEkwE(#F!|-+}=$`n;r8wF51&&v+)-!=e#YA)TmQghy!eiB%2?{R*@C?T;k(*dH)U3{!<P~X!K=ONS=-O'
    b'u9dVxQ#}M5q^NpudnZ4$ZHSSl&ZRoPXJi{$g)eT(Zzv(~d)>-1-EG6HZkz_J&@MLOys}o@A3xN;E23NWchNzscb(m;%j7k23f#n4'
    b'@8({u>ZvWMl!Em9g>$dNsbn>P(hd4-f;;maT)*o*^h{1-ao&xj>);`LfJ^bwfEL_2WuC7@zGg%}y$t(i0Mu^fK?wqY?Z*rKfRo^z'
    b'6y1imk2E^u-)n!ySi<~OI{fh&V3{7Uy&FF^@aQ?(Kot|Juf@;tW4QT4v6?_7*K=>H<FfK%JIs^L2gN_!SW<OgcP@Ud{gUw4If`At'
    b'&jWL-4Hnd=TwXJ{rB_NWd~nsqvZm0(#|bII?eqTn&Sd#ky6HnvWuf+x6y#d}%E9dvbFEV5Pt}n4D35sd^Oxx@(M_Do9`l$dHe6&$'
    b'PWSp<7J;bsZM7+3z;3fw@3o|6rU=N1*AfR8$N6(4w=~Wq&m2At*2eL5(n~s2uY+3{dX|Fi(YQPtdSAYZZDD-)<u~S_8Z_5H;~hO7'
    b'ry7rup*Lh93aB=@_Vj3B?^;WB%=kV&A}cD7TtDt#FYlux_YOBy*_7`I0^c=g5>E=^OD6Zu^Cng;xa_QScRefbw*P$dZX4r<rD(0T'
    b'Sbdy}-bL*qrqF?w0@PiH#hVkBI#IP1?4JAPnEulY8dzKm2gsyFyP^T+Wo!hyE~6@MskeQx<qmb*F)#gmdBmY{j)_e8?UaQ4+k+Jp'
    b'q5K$xH>`0JK24WG*~?^lZ5?~*b4RczQ|zyr{T?y40F<Bb!#s8MeDwMx@mcaF?{G`^)eYO6Jy&O9Yu*G*nRZtt>H6;W?^E3V^`|&s'
    b'dvT<w%4LsJ8>+JDj4D;5FE8E?D|1?pY@6m-Wpo%re%3a_YJHhxFZJ*E8RgR36su1(OGzS~e*QQ@Ymk7^cyd~fDu?8-Szh6McCEwq'
    b'FQ#<RcZX5m%gb{ifV_(tM}F|9?-mbe_9asPT-(Har#BofU>De(k7sBgW|{k4px*^A_L#h~+Mo1sA2x%a^|8nArX*O^;R`)=-2nAB'
    b'>#eo_?UIPC`=U9=+U<8yKkxY3a@-K+w}CY+J5}IvZ!20-$|mxT`EIH2-Qwq~<dW5g@)^;mgXfn(y0=aNIs3uil`JmLP*7sK48xo8'
    b'4L`Zz>i+pZkDi|gEO8n`qqaYV!E#V`YTw5<?6FXf!M3+cv#6~19u2YDv7rEud!6rg`t0XQ*4LG`ZY7MkAFVcrR%bp*jZS4_&!W*3'
    b'8*dlDsf$zcZOc`DekIM4RZm8Z<{9s>=Rrd%r}OD(y0n3fZ)?FtoXMj<RiZhVbdgP2OX}mL<z|O*o6u`FqOBN~BiBat>8&HR_RXa4'
    b'j@g3_p0^D15*)3y3YDLq!m2%Lr|PD9A5J2^-Co9iIsALm)=|&P<t}ee$YO~<|3K989@ERHTi<W;CKYs#*#2BP_|IO@(P7_J=cNLE'
    b'jNv%Tm=|3P-Q&Pq$oqYLG5C4Dw;?Dmazkfw3}Z!haBO}a3rCpfPSCiCjMS*7WW25>g>@{r7?H+9Wzt~F>Fhf|jm{$<!d#U(?#0Rl'
    b'URm~QEulMoSP>vi$pzqE2|8lu$Fc2NXGR}~>-XwHbdFum8FzK&k4Rps$sy<Q`=1Q=NN}5g-x=tIc>g}c@QH^%8Q>8GjQrYPo~Bm$'
    b'lcgY1)U@iCMc&mKMWVNNsVjZi$tKVL?NN<~O5sf6X-(v{OV1Ij8<~)xQ7y;5f7BX!!GAD2;NzKyaQ3+?>i71i=meNZ?X`x*)VVV}'
    b'>!QQwp>gLYn@L4d?a!2L7G(AIDIe*A$(diyq2heJUL>@y^Qwg(LHPcveodybDy>TsX++mbB!Ab<T6O-_d-girWa@epzNR3RNzX%G'
    b'FKw+M=T?^A6TIKtw!LC|7vUM!+O5{j5OU06_@;i|jdEQys=|?8)JXYp>{j2B+ZS`zQ#Z<;e}jU1X$ccoF-Oy<yh4Sf4(;D0zU#$<'
    b'%`Lp)wCz*r@zoWi&jD;*4o1*;O<cww)pLmkzO%8AXur4&>?8lP?y}lp1!FUzTEuoZKNgGmau*&?A*g&g#$C3;-f~yN`>pn5lr*$I'
    b'Qfxb~?9x?-3lqv=-j2_3%XX_RR$lR2x@)1!=ivDXF#;j#zk1P@3iT->c^y3J9AzVYweL`8@U@^Z*>Z$uZuu*ifycMoXufQ!0%uTj'
    b'XM!U8E8T?5uk0oWy@XrUr=)sQZSX9`TgPQRYAx3%TVB;HQ44-`DJB|i^Cd6zcI0BbzE&!SITug;XXQ3OZ@Hz0UY3eoS4ZQZvbu^Z'
    b'U_!3fhA~%%EMHqRyXUtC(xK>(CFzR=Y%v+eOyhhz!?A8ZhAO;TY`6dBruMg5BtHW%x!1~90g2l4m%pJ2bY9j>-5INj98ZSPr`V@b'
    b'jaRzqtK+gwp{A3=c3J}(kNTF8BF8Mx=ojDScJLiHK!@K%x94+?9F0cM`_)Jr$CjOpL2pX4*KrT1>>9BMaf%f&nK`q@N2=96G?$Zd'
    b'Lh5GAw5<d5NS~<J{+f#hIoMC<B;Odm<8^S|tz+nZDUJPUDW>Q35vAiVVqTL^zkF{XV9q^wUbZ{2&}PF6QzIkI>pixcF8g}TtHh{_'
    b'U#tr?twD$2`Nwta>q6XNDcu}JjLZi<J2Dd#-<rdYg?A=yix(NV)J9+M@XT$#Z}O`Aa$m$DuG%dGEK35OO2u?fP@~zCi!V~Sv|XJs'
    b'-`=X-@%lgo3+z5EP2gzQ$c9a@J1X;0oeQJ;{@6Rf^Jrfglw;l81w&`=DY!KlyMsS6aC*tV8Fzjz_IpU~w4>XfR2mgP4XqA9x9|&#'
    b'%iJ*j`Y^+toI&MNTmg+Ss>|L0_DBk)sF3=5R8oruub|wlMXw2rN;u0W?;aa0PdPK(-XE3n;QiZ&2zx<A?XIK~U#p>S+HSh+P`Gv^'
    b'&gZ8t+5Q&dr|yT_p<b5W%C@}*%UiWT`>*>KSwd21_7g-v{VFRQhx<WkGF`Ha(|^HDAYbhA*+CxmN59=wQm?-POCaPAOVcLL6~pzm'
    b'HD@Y!#a&#Fv(EpRy4L3Pys!OQ8fuhjMnoAxiPAwTNghaaaOxmbs9yX1`91jey`MKD_TFn<*IL)Q_Gylc<5h3-$B-ss@K`ff5V@u{'
    b'5t`X5YJMDrNN*c3k-4(|f$>oXt~&N7G>_!7=o|VuHQy@o<K`ZRQ5;+Dbx!N*r}#?VWXT-uLF<wbSBLA3cD25B_P-V6+StTi`))_A'
    b'w$t$k^k3eDS*F$>b#SATpvh=lt{9suIPe<WvN>tiYUrlYWKdoG;rY0<_SA}vfkKE~r1u{rbdcp`RALXMQ#n4-%d^?vFF0o6t!5%o'
    b'`Oh4?4hZG2ON<~nV*sr_P%2-5ox&Z)29sBNu-+lKR&$c(F7M0gRSAFVMFICsbv2qOsF8(yoi87H`xm!SMrH5f7W8Ja=k8It`X*gA'
    b'91c%we_6*b=D9RSlNb*%6D6;o()W3t6s^|Q>d&FPJecfn<<o>;6WzSNLFwOFKE!O?)<1tK+|T~dH>R`Qew>}j`F*pFWQ$WT8#6u>'
    b'BkMHjZQ}Ow(Ht(2_n^_-hs|)GZ^YUY10K#*yPU=krY5au|J@}s21E4I?ADFHSK-%dLn$@0v+?o6*8esEW?IMn!ylZHT<Hy4IlGmi'
    b'<&n6LYHVY|CG`nUF2fk>Z${Bj3PwH69i4~fgu<cPoTg2_dNVKM{p`NB>S7tniPh=Zd;RL7*!$UDBmjThF#FhCiC9(Idrgc-d$d~9'
    b'j_%S}7*Ee~D5bG}j;wViE|H9hAADn~j;;0J`(m5nWrh?uOf#sP-_O+EQCB;!G(C%7=6Kf@zxm32IxRnrD`B7v**8Jn+h$QIZ>uH!'
    b'aVz_j-8cOU9ZsTlWl;uJX9{y0qdTEi5KQho!y!wZ$DMOf&c4&=J-^SvbbRZ@LzO@1VSoAj@UzyK{neIHp*z~E)d6eU0S_cd;%{BP'
    b'HJUI^T}}DRE6#(%y!<w>;f?8H3ZiVC;A9}Z(tx}{L(PqBe1sl=OKSyW341b=#xCdUV&U~=Tp#+a`po$4!)%FI8ec^-?EGAl$#~Au'
    b'wfGOk4)?{l*s?9HUGTaj>*M(r`R?V8EkBsq1?0L?2~tkLB69TB)1Hr{?t_(Ge@rjZ>KB_0H<)XkUy5vROaCzTaw8YTsWnP!&`yp?'
    b'b}M8v_W>?Cx0X^go3J%W=Ie69gto6k&g*kuXm{a*y%i>|DQBgvzSa-f+L6kV*RBNbX>|#9ZrFuq*G6%#bcS^2^wTYW-OFtmr8NZ~'
    b'fGhkpcpd84$u+#7VP$uH2n^-R;68)1YY@v>uHNew@It1K!v%ZD(2f@*cfC%ldVaFV&zun>CcsE@L1iJpX%7iI<L#f0Xezdr@1!_r'
    b'uXe}9OEhKoklCr7MHHZ6%}8RVM6L2%HAa|#^m_V9Ddd2`_(XC&icPMAKup9EXgrbnCyzl!*@5H!H}2{1VppPEdZ(n}Z{DGKWBRf`'
    b'owu(yBa9!fxpugnk2%u-NN;Y%rE+^bQhA_aJ!i@huY!XSpbrdC(&z#4nzRHoVcNkAnUP>b-b)#^yGawn*Sss*KOSGo6*ITLI@{=2'
    b'_cqYIJoEPOw`e%&7<FpJU8<6Y^-X=uC0N+bYat6#AUf9HUvEimsIyPhwebB1bD~qPK&a1z^2JV*Kb7_kRt=9BjC`wy*UAZYtV#d8'
    b';NmIbKpUyOszNxHgb-*I=ka6jmxpu{@2|g0XmL(&k!IGQRe5z)zn^o!-ZZiQZ56~j`@9%5#lkGSACEwG)C;D9FSG4%QVDTz@0?<1'
    b'g8n!xMx9vowwc?-S$ydH>&$i(0d0`E>`x}ht8v`S4}Hw!si3L8u+;eEWx+L9ufJ8-#<&%%OK3a4_0Qc|%FLAXW}TT2F`U*jbt!!6'
    b'ALjvUKV8agHw0gRGr;t_<^+Z0jO#1%86=3a=MKlxhQzQc)#3B|pnIF@N(&CnLgFh;5hxuxcd-=StDD`M?qwOZH_1magpI^+O8R~u'
    b'Uk{7$8h(tQ9y{48$SU#|pA)_65_(>KmD5!FEGkxU07-c_k(a#t{5ZZznjo&9I;!B5Dkp(D2@S}1Zd<M2U78r15nXn%l<t~#YF|TQ'
    b'cqN$Re&{Bhe&zRG{J<brY*dw*Vd6{>nnKry!cO<z<c>Q+OIZv2nILTj0g?Kk#nuJ9^KI7-)3#oc({dFsfCWm-4RpL!Zzjn&Y}_rN'
    b'rH@*gds~+jo&MwCzZlgP%Vis&&1G!}g>`iQa2L`oRTZmSzP-D=_1%@dS$PI#+VGn!D&NTpRD8d788-Pw^LB3U&k>IKe=LVF-%)pB'
    b'dDWV)myR7owtB5qFlt}_^?Z%VY7RPooc{4;Hzp}7`IRnJHD8)}Jr+9RHV+)Pe%wDStfw&w%i^@!{qBiJo{#GuJ8VCJzXZNLC#@0('
    b'e7VbFJxnyuS!APBk;?ZzJ>2|ez?;$E!3-v^&6;|4_x0wywB!Y3tX|-Q%<>x(APN?L>Gwy{7>I`})Yq#wLnnA@jW&g`@3+=@xog^x'
    b'B-vYp7~thOJFX|!=cPn9PR^pXAZI^LbSRC686|VNsG3WsEVpQSF`_@6ee&33Ev-sUoKy8xQCtRr)%yZJFY}kO<3&1>`MbUSc-8!f'
    b'uS{33bpJ?A>@Qx6S8KXxw%f*6gk%iHPQQB)*qzgop22nm^>6XB9B_H}1%0>*yuHX{AIqn_S(nBK#ErFJn@txxaep0LmbLS4QK=ur'
    b'oey3}O&K*YjPP&c^|9VKVs1UUHe253vndv5>iw&4aF1`rZ3XdzZZ*!b9`)K=X7#l1)VgA+yIPs3-7YPDpIukX$f$jW<U{t_;L_{%'
    b'vDK_<6PrKIFaLdy=Ej<z?<Im`x__uJ1j}}Bb>oO-c$@ybOcPtKKj>$$sGLV$jSIklN#WP{!Iq!0RE`TS*Vs;uSR-OkEe4)MrG)d|'
    b')-NBv)!P7jKhQy}na#xkAKuQey?NMxQNH?gKiu=1F4Oy-m%kahdb``d)y~TnrmOF|xJM4RW@E<P%d!X!isfCoK;s+;`B`iS^`bn5'
    b'A_kmntvG8v4iZ8)o!j~|si=#zQue>da9<<PO;a`EC`kK@VWScg<j>P-JS5ASNnMt+$ND)q0=@6W@HBV0a=d<5)*x@P8s5uub=N1m'
    b'e%#tEF`z!{952p@YDIsnV*Wb$HK&pIO4Gbj_2nCvU-9G8G#2-(`EiCMDo=iW^Cg?7-HgjjtL06?C9jHlKJX!^e^j+0)hgYKW3$sx'
    b'NxVtaQoZF4L>HWK^8@OC{xFut+YvSIN96S_mp4lrFDwSw*48V!>y4j+5_|Odr%M^wyedyIY(4QNuq%e%`g1sZTW+@q=YNPgE%%~='
    b'4;lo0tyMvF4-{`Na6KT!S)<2!l*wmLo*=Hz7s4Uy2*wmN{OY5+&}~~m_}+Q3UHy67%@$rwy9d(>zL4Drf0N9X2)H)Z7W-J#!^8T)'
    b'DI#fjdsT3tt5<T4j-%;RsxIXkS}kRRzxYp)y=8qKYHIWpRGF|3wZ4py4AHMgcZhnOf1ZSZLh>xLUOWcOXjD0{Yga^t9z*N7QI+JB'
    b'8Afi_0$<2@8o;keTQ0gqu!-;-ceh;)Ur_ta9pk_IkGVOn2GN^y6j=IFJ-|ZuhPUhJY{LHD>*l!Du23(_>KtswSz7Du;KFJ@`t!K6'
    b'Ja>3Bbf4AR?ZiF`39wlwVF7vPH!Yx5*EjC@WE_%NsJ|L|9czYIU$lIJ)7-?M7{Kb^vGk4q^QszYy-CL`jdn-#D39NVew~O9C#sYd'
    b'DfN=g`);a0w{Nz3h9%XMsT~94HYkP}4zP!OIsc0Ub?Uj8T3=@qc2DH+koaeRH#Fx0Cbja-TfoR)t#XE#$D#lJe2XHhm_9DPS9UtR'
    b'N||+B%irf6xL#NJryGu^x9NX(NpQen3-rd$Cvkvb8-D{=1F0Mz!?r>|mv7m=mN&|5w3)GWI$Ly`w-V$2Y7QhNn9`)~zTNwj8=Wub'
    b'tbJ<8DzkS|$P__hWAOuR-jJ6-ll5+EXR$p`uJ7KVy0D+4T1{Nn4gYKT9<uVq@newnmYwkI6hY%KO6K2$?z!l1y)1GK-s)+IyH~K='
    b'p-%AiWKbJCN6X?5j*%yW9ngo<`KXHPm2<6<bvf#@*KTJ#Mk-vrdfJy<H5@-oM!FM6-15YA`y4-3=I)k`!S%NN7v?s<*(LTiSeXOM'
    b'pgbF$YRBieqTLH2-b!;}+-f6}SWUa4+<us;JK2mYjgPtSWFxZoN2QL3Q#%^Ob%w_aexv}K{dW2d2n`SFPmOkGJ8dtFHWKz*ufgZ<'
    b'FRro?(7#Irl~#A9^H%o4wYsVo<o#v*H%K(wf;QyOHE&-UQJqW?v|?$jp_j}C_D4H4(pLF<wrl-wHz}2uyE&5As+$$OPD}EEUdTW0'
    b'Fe<pxo^{|XU{0Mr4=f3X>$3DMQUiR&EB+%=J@mHA=cjfsogyI4bm<e@M9V&2xwa8&+PTCcUr_gJ7^&Z)M9p8@(?zTCAXp{Z9OG8}'
    b'AD$lzUJagzRkB|=S5M7yWr*c{L(&G<fwVbhtkN(`^vxVDy4LiFI#vH=LcpQAot>Mf7LnHTZ>LqNB>deR!<1v}!l9&%i@Q&~$IUq5'
    b'9G?I6q?~H*mxcvc1;KM$D@H*mjv7*{U7c0myL?=U1{oWWl0FZZ;h+K_@lCv#;BlR9iAnMCkZI|jCJ+Ber^>?InG93^+NN?FO;*->'
    b'G|f~YN`En`Y?h`q9UiK{){MqY3q_Y!&w`an6P}ah{cx{-@j)HW=|L<Vv&W?u(pRupmp|UBeYj7lSv)5xZmau2vf2%o&fcq`$1Oay'
    b'X8y4;YTcW&H2&YSknLQH$l^P=)s(Z*9&hUXVbQxD@V)!`R!pOm8p@sNMsoy{a@Ln!vT=QT{k=bEdN;WS99>Mg+{Pz2!4Q!iw>nN<'
    b'cbILIxe$YytHS7`Kfa7)+tr1!UM3!oJN3pTR%_^HT}WX$1d6RSoEMdI&$|w-yOP;ehpAQ$t^ymg=ANzU?yI%*6)?Y~UI8?MYcXhz'
    b'1EYFbSL~j)JhJUsSEGpE`6`Hz8D_aKn;kM~GC#JFQ&U8n52}oA!qilnv%k|tpNpdu9{SBsHQkDRXNjNnY{G8lZEwLi#0okhZq%}_'
    b'!|7%mFv@`DLzyeL3CixgW}n}@!>Q7s1|48gMY`vK{08?Ge+p>NlkdKW5Y0FJ*4b0@&;CGHs&seQTuhuZUfR8z8FZ)*nq#^CZI=xU'
    b';M+l#UvlRFc$(kJ`VC6ySDqzRxy^r?rD?UsC*#$T`j&(DGJa#s+3mzobjmN1Z9SKO%&qAA;>0zEUp?9{3eSW=m9H6P8sTwn_b^LN'
    b'*58upN{-idx3Trl%_{GdQ8*A6?|pL)qCXw%c+)m=d97hQjlZDdva1lyA|ev<BAl+haX7NBB!lqaQuupo2JumQ&}o&?_67Ak@YDC('
    b')m6#umfh89Tu@K&m>*tCmcjngLD?%_i|z#Qe)}-uItW0hljy@tOM=rE<n6U6UhulK)m_(_ee53A^Q(cY2A$3(1rN1j#coMOLa*o|'
    b'zwHhK`}S!aTV3$NI#>|U4eq(a%1nah+X^#SYS#1TJ4bzU3p1aqTWU_mqYJ*rPIWGv<-6J3G1EdKdHFqH8k1%-kbvA}QmO<;bLBlU'
    b'UTiwQ2lctCu4STTca%MQb?%X>NjGixtqZSapVzUchWvCX5DupAW!1;B<pJ42f4gTp?9Hmy?y-4F5BT1E>yA^=gT*P{Nq@+0B+YWR'
    b'eZrdEcCB$})GGIDeq^Hb^77^N!=-ysUlF9|2+PbqWlfsnkMqOW=+j^h=O^vzS(}Tykh|+&8gao2ST13veyDdJ*tW9Z%RL5Q-6c}c'
    b'feKt7<r2rH)CVw5g>|jgR7iH7dv>nPg}r!x4-VZ9rCv5pgGDdQFZKeu5wvM3{nCECTs?r!`PdWM`FT}>52QqjTO+`Q6)pw_+U4NR'
    b'W{UIOrm?C|M%nXp*zJuG3_>%oJoTo>BU2Nrrnhg6CR6u|W+-0{>fPG!y)5g)8q+P*Y#<<!_Qcg@XFIx5(N34{KIKQfDRdB))et+W'
    b'0@~OxKHT@m1F?8?t{v?XDp%0=!Vv&)w^HvT=BaS#f|U|6AYJ&4iFz-(R)0E&1zyqyD3$If2|a8B3UKkkTZSy{5@*meSg7vdVbl6p'
    b'uQy}!gZ9&_R@S4ic7j^<$$+VdvRnmr`ef4I;z2+ip?NYMZVO8+jq4?4S%J~J@|)!Zq4By<4n<Apo{a-=B4b^FA_SeOn-?ILhDyD`'
    b'^*5DoyL0GX1g?v;7JC`}7T|2fKL_a6e=0IW3GY!_8h89J(>O=&M{gBc4PIdaLVN@2-}%xbY#L47+x7PCfE_^nOAh?b4Zr>QDZNzc'
    b'#4u2xXMb*BASrCSgO0d2EuOrcduA4k#%c*nz5%yqbs(NxOCI23cT;&}t#{=X5mtZT%k5vkQg*HNovHNE*|52Z)8R)epX%k)>AY)n'
    b'FbY2s@bPHtwWuAO{NBVwdZXxmJZ{Yuu^8NL{Vmf~Dss(sjKu@#bBX_u%as;ZM!Rve(PyWPdsKdPfYaBy=R5H@MM^{F?{JWE5*4(+'
    b'bZ=EmP1`UTQDTLB!+J`zSA#}LUn1Au<E0+d>y$5F(WBHwy{%z(N>uwfTZZwxMVFk-YvFWk>1yNg2L1H{2GiF$8DdY-K+{I4Zl0QD'
    b'KiR4VxuzxudiFMKMcnW87u9$K!IKJ=p>$i09KSUk8q;abZcXFl1%WA?*@x-blGdk+e(U>oGvMR*N<+S%`A=gu_~z;AP(0Q5`MQ&%'
    b'O?9c#4J(ROk3gfQIJjtaa6iAke1Cd=+z!j;cpm$kUhY9UYn;#C_kvg2(-LvZI+`7&zB&;Kq=#xdaDA#?rzS|&el<N~#{&ni>Q7l5'
    b'wjIHXPkNzipYOUd8pY}Kq;U;p_uW=n_S5AFBa!J!j!ijk`7KpmLkh={)0V`-^z4^4==wQsKQPBkv^oqPpQ1Bk_#*t}$~iwly`e*t'
    b'@pwC!_65K0)T7J{fvT^PP3D_@UVpI1caqAPausqpMK%X}-Q=q(Hk>?%@&KK7lY6I_*C}>;+!tQlUBxL!5u@2K2Z)8Sdi-j7&r9kq'
    b'^u@|4SM>Sm$Vh$@Z})Acbh;-r78?piBTMf#^jRD!gC}Vp?C<7$znsm~egD<Tw%%zndAHJS6)r-1R}+G1cNw)Bt44`T%=rPEO@BHE'
    b'Z(aDO`9^7Ry<0<xc4*<Q#@$hWdJ~CS37<CmPRZ{J!6@bWG7NXBVb^#MTD#5JpG@X@`I|-0jzCJ;wn=6HU%k7{)3wHL?=_F=dj5Gi'
    b'to*z8_Or8I!_tJiH_ZO2pu3BEuKHoReI3tDtSr879j*5{z5xTTwSe<HY>=;WdQmt!awg~|-p-4>eU?h><gtuK^+7>8>AaP%hqu&1'
    b'Pw>8N|GVe0wR@x|ek2%9MW_L_2VXsGjD2ZaJhv~bC1BaPgEvwLlU8jVil2@@Dm8O55cP1?yeg8NODHp6z|m$0z=;E$b}j1y!q$sZ'
    b'MkFD8pG6D%<;sK2p}m@uxcG*x<1gwj30HdcrGC^ZohMCLv$F6|*cP@bZzAgvEzOe>zAPGR>hI7y%?Cg>$fqZ9G<395Y5gfC88`kI'
    b'G}uZa`3P>tH<|eLq$+yvmChK5;#~ut{O67Y!ya^79CtIFL<5XRrA~K4n(}g+|5sZ^x8x8-tP-~d$fAGQ753(mDyH5$H>tS+lO}=Y'
    b'cea(>P9zwUQl&oSew@e|_lr7R`mpjNb`!uD7`0AmB~R$qj4dF0R-3P9;$jkMT^f2ETa>PpkoQc~{?@iK8MpB*R_YP+WX5EDTKYzH'
    b'p@Ky7zWtKtGe5dE9>nvXcFs~cLc-E7Axt|bNZ8zAb@{j4y8RmOD|No9;TP~YGUomET`9`?G7M1j)xOs%EqWQhnAqEq7Lp=JUL_@$'
    b'uDka&bgR$mOSK6f5z0s(HvjWLZhx&tj9JE%EiR3WiXd`*Tz?*^KpFPOZaly_D~cm+*Hk)rN40LEGPZXKRFdS0<_!z9xV$>Iv%dy0'
    b'imUGFH7eEFcz!EQ+SLXtuv<dYemYp)G^N2ZIAf8xPu_rfK>V<=I+_{Uv(N-<e2?Ox#dsL*hy!QzM~ffQgW{V9jXXH7cH^F5<V@;_'
    b'E*4_wcs%0tA#sv8Sy$dU`BA70_Vb^9{wZ{$=UuCjHENe7n>sFY<K7{->}E4>N(Ev&R<5B4PwOu79j!N2MK(jWu+7mMSS&PHeQAK}'
    b'KqCmnuXe!3Fw$UPPP*<_S~EeUdVrRZpBLQT2GHlW$D7G<*g7n7=DFtUUHQ0JKj%!TXF)<A(cdi4kM6^<W%s6|dODErv>%Sk^ewnE'
    b'P-C*`v~#L#zx4Ti%S0@g>l42Hca+3-*f90gzd8C|f8S%~9ZHJy%-&r<%Gyr14mx9;%9OGpqInkG(Nx-4=(n_Cx%-lJsPb)Ep+ObX'
    b'B<bAk^dKgz#_#t9+_V8ZBn|;)WLm}e;A`cY?mj<#6mX4)_Rvhh-IOTCb5P^JH}p*FHDJUyj8(X)FP!pv^|-vVv%1>=?pWVdOW<U1'
    b'>ky~f8A&%zSib*vmE4mkbr!JLMRTQ55~@<8+6>Z(VY~nCZ9nYa0<`_K)1y(^4=2YrdHU~Zm-C{oTf8ns2`90y8omW1Qu63b&)eyk'
    b'r{+rP2sFMfhQLf4zUtkiC`svtX>9ZNB3-op__{-WjxFu({qk3wkm9wo*x6sn=}#XN%XG%@Xx;A!-ZpD2A6B_Oj~ZhUy0?sNTPqnK'
    b'w)5<&kIs6>^qf8Y5iOv6e~!kdcFuS2Mz8!{r!$mW5Vqr_eepF~{jd#cUjOimT=Im6=%0%rjbD!=c(V%i?1n{FtBTcMEmgZdftq}U'
    b'y}^kc-5jAZcrSoSseXDpk|+wbTXWgggZJ_6dCImSYMMZV;-uYc3zlpBdQ!MVG~`P=oXWkwY+al(=`t}Uz-ZGekG7s#?WO&Ee~)C2'
    b'emS7Wd@Dq?ly`Ex*Dswb<y84g#oOhyP#PgF@4NM=D=t|!^@ZqrrjV|R`T_pyNv%8t+#a2q*j&Cvu>1Fe&!HwxdZ-;-8e~&9jkp2n'
    b'@f?cQ<04!YL&PsNH}^}%xEQW)G|V9rb-wS-J)%AEH*C3jc^9`=x(dVP>AA^+{`A*}ZSQWxVtj`6d5FERX)U|vEs@{M-PL9H8J+On'
    b'DhE6v%*k3`{B%wG#+LTV9(%Y~S#{G~Y~7FUaoYI$&a>RJlQZEw+nR)Sk!+ljuJC#j@Nc$#o7eyuh1fvlE)m}C4$jL1^*;TPC}DY%'
    b'!$E#Adhli7>MS}*uyT5VPy{~cxJBpW!>A78CM$!&v}brpOMg!ZkzS9L4iYM>MQi2(+!>nxv~yc$KusP=y8+X5*Pv164|Iby;h6@x'
    b'u8s$KyXe3qTX5bcEm7DFZp()#SuDNc)N*dwR4WzyU_zsn_K0T}(yJ9Y*8`|WkO?8fPxl4mx6iL0B@z?qmbPlygdC4HkW<ue?N@u%'
    b'U2iX+FCU6uxQmd0UY$k8;|7vTPb+|$_@K5GaD*%r2|};X4FB))js~k#)M-YzgKuE@G~cY+Jy|(-ieH?^&X(7s&2j7DUL<G=<b(bO'
    b'qfXY=^irM?y#O3i?f4V7F7I~sT%8zdac&=)168Q8PLN#dB%yz27IEMlueNE-US)uf?JZ8op*a$#0AFE$zH_@v`%c10t}Qcq1eo=8'
    b'm$^2~0fEe4*yRs%+iknK9}!?B6RG)Dt{BzbWxktT)>o+48tv~!!5(7ajXjlfSo8Zk1RAb;REY7l`VgX5QyD$|dWb5`b6lsFe4-t8'
    b'TVAH>TYHrc)he*JdzCMe(1>Dgu#MbQX`|F${DB}@gNyC{F@x{8(<>#7ihmb$e6|JhD4LGA3&ww=Hpy%|wyYmY_re(d?^(X}7bDs|'
    b'o?Ps>JKGq-WakxHRH;IF#!Bi=$AF)seQs3<|H-GUoxXd4^>0djE7=#Osc;`Iu$mWo<~5>v?T=p=FGGiRM}(XA`~oHI;p>Mtpc@4&'
    b'(Ctw5vkx2NCDxvzTfB*$=c?CE#<SLWF;cpzSf{}IovPfd6q|F=@&3W9^GEka7)NEENcM=})*(KAFGK5Cg4E-}$>JzdQFlj{fB8#0'
    b'+!>b>!Ub(T-%#rYcAvtEp2Ec-w=!>#Z?CcXu5xiQ#~oz11gSRuQ7e?a(-zL<waW>{q<2w&pF|EsGTx%!`6NxX3e3;%X?U=af=z!j'
    b'`v)3BwvDkl2_MCDiqN>3LA^NMcMkkuRVR98k5`PXkDNLnuwxtgi)$Eb|Cua=m$UCCHyQ0f1bDgM#W{!1g?u(WH>?HtID!O*D8hbv'
    b'Bz|)o_TnKnuJw-9AYFgWST`-gHjUHy)iC$9!%0wI+#xQOO;nssjT<NoaIfgluMB9;yFs-EcE+{-8kYBsE4=?+i>x?*P2=y6#~=9n'
    b'(r9YeSpM@fw?|^J+aK-eDC`W*9Q>E{b~(%KxuiJ6$s#Um`}WS(^!DipvOpSQV>F(A>u>0!PEJNMo@IraiA}zucuRvHEd^(=sE8qn'
    b'vi&4IHDDzCafhCL7Z}K+3e)8bGUxUYREu-Y4JvTxpzP5uc6aVs3-)eU59y#ZiwUsLcH5WvbCOOQljXWrSB0@OmA_bmc2ylEo)tk='
    b'EPV6no8oST*}vLyUEpPE(|~Vu_0Y|@*M8>Dv9(B_w^4G*2B-SyPH8npU-^yA<s#{aqJXuIuyB@VdL39^*sff$=e!q>31C$}(i<n+'
    b')!xM9j|lerxCd^6+wU7LWbDy+-E<V@-$8I`2^@K;3$4q?Ms{<&Y43ac&ZTylLauq~zv5sQWo$#^F}GG5aPR<w^?KX>uu5lrtEi**'
    b'i56Z1|9V-*Lzi=Fq4a=&_rLz~WNdG6kw3s}y`{;}6zrkGriBWaH9VF@mCAXj;Ew3COua-EIxQ}pk#<o27?*k6Ve0Gn7>#XP@ww*d'
    b'`-hd6>lh^E_K~5=^zj5oZ&~~0Ws@EzDJER~XE@Pr2e*R0#Q|UIt$X$TqTeV4Vw|Dp@=Xly6R2K)jPtBvwHIgP`cB?Fas;$zd>M#h'
    b'(>XGOhX~Xh0=z{R`P$o7{@9Ia-Acb_m7BL?+|L8;9ZoRjSqAY=M34HC)~P$FGiLf)cPii6oz2FTiHN@*)+$$Ze0|-mzC%Mzffc<o'
    b'@$$ex!8<~5&%C^LCXH8@`ReQ-tE%t#^NWWnWWd-E%kTWNm%U`EVkv`(Qy5+Gu_77?Xz=#VT;__-mZjnxOVGYH)m!WK9~_)w#Eo8d'
    b'7d+E=rOeSYz=~aQfL=n#kHtL=w#B<C=T_tAD^dj(Dl4+g*zTCahJ;=deEqVd$43}2r{mzNEu(RJBhF>BpRb$Ja%1h5-tKecA2?8a'
    b'^lcmb<QtfgCaPY_;!8pnoqd_w_2eP-*g5Jm=HXv&)K+4du{8wfBl!o!_*UO|k_KII9~>ckrfL3O*7_UkBFs0Pt}3WQrKF4f38L)x'
    b'<AWT?=+t~5g18C$StGbCP_e(>*c=IxIlf(7-2%~fKYi~?kmkmPxIbI5SuR6UgQwK2+vRT8nS|Bbs8r>9$ItQ$Xf2@yf#+bqq#_H{'
    b'YG)p${-7v8nLPv<Q|uOlk)GQMNGhdR@MJ+8SK-AM_<a59QDI(e@0FQ;nwOG&hG&q`m{rbj_F=ZDtK6yGTdF)CA&zbuhiQD8G_VWw'
    b'0R|I+3ebAsnbdOM<k~9=pE(YbnyZ=LvA>(frCIA)uXm4%8`WP8HW%O5@n$7(F9I}`oEb`^)%tpkMC(o8#&XiQmtK0Kzi)lN{NM<!'
    b'KlF5Xsedodm%LEXL>%G01O%>MF=S4GTlS9L+*nJ*YTlsECPp4V;Q6QRk<(~Bx85Cp_?KdlbTQ;>Cm)I*6r5GW8FCC^`&ip()kE{('
    b'Z6H?*hQ$%j;O=IpiBf{86&-$^g67=f+-O=d9>#@lsV$nlw1woF)s$P8{Ar2DlZBpcPfP;tPuu~TjHUrH1ITv!PIQ=JRP>DQwS&d='
    b'G85C~O(#u1laF#g-ehGBBO=z_F!ZAt!afX_F^&??cDr^c31FET^}mbKcHIX5%~ul7YULH@jZ%al&hTmttE<OOIpJd+8%MP79q=(S'
    b'!k?ALDjEu={vECa(GV)7$49m%8JvHh_W6&Syw;A>XG6!O=;Me0ZrON!$5QTnijdwf_6k+RY~{Ruxzt^FTfVHY(Y!AmukI?k4GS5p'
    b'lriddhtkrn2N48BN;O$MEQ`)^=kC+!ppGf-{hjhw7y6>lYbO(Tc06w>z0*2*K@Y7HFyv2DG3YYu+C65Q+ODZJ(Bq1@pO;hHUZp#x'
    b'CCDl$K`k3~-{;r2J%kWQaCkW1=e4w?b-L@uH!~ckR=*>bXjlYuu6y;e_4gc1svMU`*#;Nf{uehoC*qn|O=G*J%u8aDwd$S|TN6V@'
    b'79~b3O0~CC@*!fsvi``w>@4^fuZ~v7;R{{2rcas17`6#lM<f&6Oop0xIQC#SL7lz-A!M4v;6^L{z1JC4Y~Tj2aDP1)HVKr+!q%#x'
    b'9s(~v4D~3}ME3HRO$XTq-4W6Q$yL|p%IquI$bh%MZd>r?sBFB_xEM^Um0cxs`(;Rt;_z1QuTssv!RqhcrN4vhH7jrNFb(mg`&bzB'
    b'f!-~NX{{;+%yzuQcUeF5x@a&I4Mx<0@*BLk{tMT3CCP&@p!ql+JE?j(U~bCZtbI8k)x(qLfsbVyDApNq$`7+GeORv6ze?@daOu9f'
    b'cB%rr<2_0$4#VeAIJ5MfXUpA>`dv><)6uI~Z`1G=-A1ZPWpuW7?2$T;anjey*^qZH;(6tl<`eyT`eS8g?5)7fzuMOc6vw5)++XN+'
    b'-m<pNj!gaTWs^=wMgukEv;mDmmR49$4HjIQj);MBTTLcxt9|O`#NWOt!LO`ET7AL}Ey3)R^k+-gK`+Cckx*~)j}-Xzd@Fcxd&c-+'
    b'+PqBePzl(aqM$a6JK4a7!Jb_1TtS3n#W_`7jKL*WP%~AzY{#cIb}5OWom5`+ARk>-l_-{_6?>C+n@&&`rL0cX#@tv&*1!I;TeB6%'
    b'j36A^b}Ftt+!O7`d@$cF=@NMhRG@P_NP>cxdrgxd<-F>Jt=G7BU8<e-5Ntz7=rqILo2$JYo&}9&r^w-tdzvp{HkMRKY+v7>?AJr='
    b'(a)K}Zug5(T}$tEBxYx`0V2}EVgSM($DaU}8F}5?YlaN`k`3;T(Bg}Ao3FR^6%=`O%Vfc*&fpjNsn!?zy4My8aIv&YCoXtPi$~Y!'
    b'{xs6+-Fe_L?+&MenTp<$;y%?YL%s0%7UGvj7y~Pwx)^_~VgW}Gqk!cN0LM?Qj5buW`?@@_F}$w#!qRL^9?=ug&__li{ZM3g&sdXh'
    b'F*liC>}9x-RTeRQ4xJpo^zO&7K&=<{W))z~Ht#Y)H`ch>c;Js#*;X~u^C|0sT(_|dJEt1`$QR2peyMdPUx2yHh2*4!tML&qD0t!@'
    b'pl|DxJh<OIK8NLT=^vLbp?V?wkn2<Ch#j|QN5q5KJUu*}_pttG^7kW9(6?iCaw$)o!K%dFnO0;4-*7puJmXJZy+;$2C818y68x8I'
    b'<ZN?XzD{Kzqn|&#QD=%SEo=A{kzj6dXpu*f3wB@DxY+DWC}sX6KDz7is6W$;CT)o!WhU_BQtVv-KQy;$I3KL63(TB6_aaN9hBU)p'
    b'prtxf`KHIB=04Wy&%@tTFKWb;GzmK}0kD<WAzMEmOOiZ9v4HWTk}M5(QflJYGtz|D<K=1JmjEQd{4UOyjq5JkAlvt$R@By4aU-_R'
    b's7iZMG`}V1tK7?((eR(=3~{o;Y+u`y52-JWHLKzV%EceA>20!2#MQ!tIl6Q|fY;=64m+_dmtN-*EFQoimD5SN(T=~^!AA~gBYo1='
    b'St8#my$?6B`l&V72Y_f7LHpnRdh?sQ&C7*x>)+;zLUVuU;{7bI$M$}&oY9D^oZZ*rTUvi+&>yn2X!uJegB9RSXRiiP-kG{n$yQuV'
    b')SI6TiU{Dgwg<zol{LqMKHRCaKR@r;V$$Fs7%$2723(w;PsM+?d?%f3&eHR5jSBdzsY-Xmww@#P1&xB*7yQa-)U9gV9MSKvj2+@$'
    b'Gu+*7&T#f!eiB78*f9olzGL<Xxo$Rfesydw4(uuIfQh*ek5l{UTaBFvPtVVne=JXeAUp1!HGSqS??Z0w+*_v!?UmMYwmLsslJW=t'
    b'{TiqB=BqQ@9DJbN$eRLfaCD<0`?=d*kcI_(f3>d}-V;9abGDan!v35McKhZu0b3K4a-P#+$iDP9Wp;$}N#C6or&=-z7l+1v7EEA;'
    b'Yu{lEItpm)Md1A2Y<nh&oNN5w*F1hZ1!=Du_I@`%{XFhQf>;7q`W;e@+D%3417lLlWk-;-06E~n9NH$*Ct!1IQbQDMxO}b+(?_$F'
    b'Z(WCu`zg=2rf5D+@QSJ8%8Ke^`zqXEysxxsVf;;9D)s4aUT--6o^*Q_CA+9s9j$_Q-(kkxmyAB9YpZM@m0L9*-(;x%0l-O#$Idd5'
    b't_nHxyM5vQoxFS$)^Yz(rNDbp1PNt4GJJ*9yg4`<_+BzYeC~%u$<vD$G{5^vJIQ6FwzGpSGgmV(eT7_Dd|&JHseV{ex3Badg4UBj'
    b'hOGqdv-i;>s)Y0HSogox%@A5tuBK(X)WSG<m{^KuH2^ZOa%3NfpSRfhUUzAk#neHaYojNeLjZmye!e2Tcpe}I_5^yk=zYJ6Csj}M'
    b'nVt*jQJgBN3S83QIzwHo#nslkaFQd$G=HF8*y5t0`COvq^=##J*2Umg?;XzC?sCbxgLoUBh6^Tj&D|JT&-RAC!|tR#nb$^*ivF>I'
    b'()#O3%-Z6wqzcfhy(gdO13Za7r2<f`inQhgm#pbxZ#T9k(IG+1zU`C_{`j}&4<8eUp)X=|CU<G@*|OW&r|#Xi^_K0B`=Ewahl9S@'
    b'sJ{t9*0YYidZq>MnZ%Gp^zeRQlJNqKef;XR$c+fRglC0MlCWG&rv77m=smZqa`*pvRawTs9lss;itzj}8kmWphlxPH$>nJE3M|WL'
    b'+y}v7%-x6WtOjpOl>nJL^Q4N`l5|xXH_lYvJJ4fg>m8b=hy;Rl>>2Wx+LaoSHj>a^t_;3T!~rQ5lWw?hn!|H*W2m~=JsZ%@-9#-p'
    b'oel2scsY9dwWCe2X<I!A&1K=7(E#%I*W|hFAm@duF#e3?MT<QC#bf$=Wj>Le<<KAe2!B0#&Qq^=+!H%~TG^BBKRQ^%cBNuWja6sW'
    b'yx-T)BUa<?M@A*rk5OYioNx~F-FBPT#8fIyVz8!$&0DK-%jv^y;DBBZY=vcF?1|i^Ubi|c-oL*2p`zcAjXhY0L_yA9y=r@@j}H`s'
    b'V(|oNOO2@(u)BI}a6_(6TAA>DtU<1Z#OX>u&ztR=*E@n2==p9OpZL)sK@DA`3>mr_7rK*&;NE({&od2(Qe$x#ZM^2hx+)CS>Ftzb'
    b'4ZdA3;qnS&d*oaO;ry~*ck8o`nAe0>gQ!Y<?;fa8ruXnMmR-AY>$(q?@V1D;G19+8!FPskny%+mA$~*rYUV>(GTJ@%I_i#|wdK5~'
    b'P?H*&X+ck^x*`sHxAn}3Kc8n!Wtl^D=Y<JD6*GLc+RjXHB!p&7K2@%h-t_C=<+Y(jh5M>jO!krrD@OYg<45ZkqnvGq-SEQ!ozJlA'
    b'_Mwx8p2eeCH3Q7?2UW(Dv_HBQGn6|VbPp80QuI%Q6l*dLLd24H`aZ$Z>C!ce#f*$hSyVG&Fi7+lDGjL)%rAqR@#}xpXI5e^L7@R>'
    b'W!b{hMcIRq`T^07BhbGLk>Wi1&p*FTCcTBSDI+xU2x|+a!{6i}&Mcl<{Q*}8_0N-M*gI~n(W`ly)Qu{mg=;Jhsukz?+lSKlFZ;ea'
    b'<zoP~bG(Nv?jC{;u?o_$b7E!=w%EE-{Se5a)x3?<stlXQ5)<6<?WM7rmur=WRStnhE1@?oKH1FU)wI<Zj__Blzi!k$x~c59Kfg-H'
    b'm&<T7m&&d4ORuvyzDPco%G5Ms^_wNt0%Ld&5%l*QE;X^`2q;Y$IJR^z9hfcD;@6Kn;%}wO_6$;>IB&OIJPP=?fD>sZ$sJ{8tPj8X'
    b'#ujz8uDzk(k=JQdh-v=`wf@c-ZLeQo#~h#6O81H@&gbP+ha9w>C_$5dnb!$-uK`_+N$9D<e$_1b%70`KCF9#FguIPOSFm)A??Njm'
    b'>pzdXg|c>;>wsyA$7f4D%)*(k$EMK9PP2PSY%%^wuZtvssB+Sg3!e(J^~dj6FC7_^JMu5aw_I&zx(2#nvr-+?Y3{n475E!W+nxBy'
    b'{jvVZ?~cNO(<$$h*qhGtY}by(C*Mu#e^deA@ra0A>M2DG_uQAfIQ`~n-%5Oz`Hn7|q;)2`nCR7+WkDyE`ecZRO$&mhP`*y?gXNiQ'
    b'L_>jRN#nfxdFg~6k?}-!PT-D_2K0&?;z<$IcXm@u0cZ<P8gp%8?d*YDf0ry3cs-qQ@Vp;8&8I+RC3Vxg9P?ovCq0>_0Im&>c4bc>'
    b'VIq{<UG`JQcJ&_?Ep3z2XxLq?U8GGE2)fvT!QjbFT;m8!-|<S6gU2+G4+gY!`p&XGoo@6bC@;SKq`R((#}I=$=w!@bPF`@(q(fBC'
    b'm2P>}Pq@t<?GkoyM<@SuU!q;cwzO^8<g}c(rgW$8f3RJ}i%R=conBTVI(tN83witzgXU{iVVd=KqwvXT;*SJDO@<RIOW($UBem_Z'
    b'$QzM0i|@7Fti7BJlY=z&f8UVHad$IVAvv7N`K5UlRwIh+Fl_(WyCv7{JtYxgdF@0X3U|RyahvL`c7SOiiwXJkG21(GErjuow1>d;'
    b'XZ65h3+Mui7gKqcA_Hs^BslubJER9~g3jHuFcK-YX|MM!`n6)ePUYUg9K~u@Nv%#4p|PtE{mPP*@Kf#E0rh2mE)NE8ssp*`>smc('
    b'{9fFh{=3^f?$<3}=DWhk`)&ySTVOv9n_i50wIwaU9%gBtfn?j)0V0NneyGVanEC96*=3zmcUo>2wfU@y<m7VvbQAjkg$yZ}Rmfnu'
    b'^djcU^E7ufC4RYxf6GK_pAW4+cC5Xpzw`C(&a6JpH@*8<jJ$rU49>LuciySeV8q+u_L2dxyjHif;@iA%T?A`%hfZRRPP;h>m8ebQ'
    b'W#y|?MLpwiqu-0gLwlwX^F>9zRQ{my{#0}6pQfVQ9zCDM2-W)to#v9wg`-6UxL0yU-0#1_9Ja7^p5S&+=Q8IxORtCKuGU)cw0P?)'
    b'jg#|TXQ&0cy^t3}5@PxX12F12l@>RDF<L2|N4fIz;HnJ!C)r&Bvjt_iqc*B`?gwS6S^OpUM(^2nvWL3xaS=^;9&L3P$mL`0rF5XA'
    b'4GgZ}_FV>jH*wZ~*>eXDt*Sa@I%oeHJjZ3*T5TKGdBXpEMeG@<EX%!{9c>K|F0s9FLZ#Z)MB$(YmRCvW{H677<*E8#Inq_z*|Z<~'
    b'bAMf#Jz;o#*B89F?e~^wuUqrocbO9BgQ&dQuK4+_kM5twY1RGBSK{@*(DeND{HC)L#y7vugtwB=?^f^WNf<JX#!Idx(@KXNmA5uK'
    b'_I*QWM5x^l{dkr{#2E&z<(ZYvvqgSmBm>Pl@52m2E;4y@3GAdndi7Uln-1^Yo0B9J44&!Hdssb4bFi7CFW636`$c$iK4YvYZDq8c'
    b'FE%ilYgLU3zmxvz&UHC$r_Q8#nk}1Q|J8xGd@#`$U5{N8;kD=K!wOsXx4)j$2CYCd*UkX-iq__Co1S&PaJ|)Sd&E>rn;+uzk&r1J'
    b'-p^}_*K)`?ABgDt*b^guvK@CWiU{V-1<^x&c6na|;M6LePp@gK6Rrw?Ys%)r|K%@dy@WaIisJWWDo*7pN>3N7xAlFO0UOO<>3A8h'
    b'7H7GP|3wRU*7+oXd$*&WADy=|<|64s<lcKV8&$QZsCSDNs_!O9AIbI!d!5%i>1pBQFQ?FkNny<AzHCNd$Vizu)tjT~0up1R(P}2)'
    b'`g5AkfDPNS;tjVs;nsH`*})cW-|SuMQk{~pi&>XowCz@eT<^}jh^fQGb-0PEw>hU(;|>19^Je;Jo4_6F*XL{+>_ARy2I*z&T=z<6'
    b'GMH<Ns?#`xgFnDZ{~uG=`m~<=b^n$IjcUwP3Js!kkR+uNFC?81kyCW~+kf}>dC}*2d(S=7;JWr+Ywf+)?#f8(b#_{vhEu$}n>KBF'
    b'mDZrgR9H(*2BBI9mFSx;Mu()lt=)CH+;AmP+*N<?FgVcq!R$UMt0J@y<W$G-QE?eC=I+v!-rktJ9m7C5D3Cz@9sic=v3$QCP7Y;_'
    b'IK(q3f-mu~$E>s6dEiyj{7DZV+EBo~8m7^gg3TtQ=dVUTJ`S^ujesdf){GCIyiUz^Vl@FS+Lx_{_Go(Sq88_m-L_M_Uk%OU*vb42'
    b'TXDBn->@76*S&1<RMybhI0&V^>=X+ksj0IY+ZYeFwaQT){&Z|=h$0@euJj>)T+b-^$U40mMr@@jvtopWoi=Hu601NxnCZv1>W4kq'
    b's1eR-n37U_SLJ3KY=4ZVwVqx$1b%bE>3#UtbGxxx)<LN2pDIf7Z!aeZkJETISC)&Qb%G+Gi%!iBv~S2Yq!BVSMqHco{~{RPglrK`'
    b'wzW1Ji$tKDSEuVC8{1jFx^Mg3wm*iOWTkc}E7tinJ9iOdn9d*F_4wCEBwDJn<XB|demvqyDeb&C?>rU_=lY6k^ZIx!=q^nsayqMv'
    b'>8m_BEqY!}sRZ$kdHJNiR)pr{!w28~g|Gr2LaK%!04DH`hbt<1KP3xDeltGWWVI^~uXYR?qrA1jjrm8KPlyjK@u~)TaVv8=6r5J)'
    b'2UBtHeX_Q&nniFuA=^_ieHfld>YuXRNRScaq0XcVE7BYwbv8I2|9}<ee2&4d=l1?ItjBGJIo^quUr25yG+-1+92aweKt?Vj=0rk|'
    b'x48y80e%<DS}A(-z^e`|_Ph_}gZ=S+Wb<C%Zg9%k<6CR9H$rRyn)=qVQX%IP;iub#1CYaK|LryACp!eI-1`%?e<z5lDqMxx>U7Jh'
    b'=b-LgbK;mP=LtWsRTHUo#9c${_4K+rxhj=VI<e11KN#DRy;OD_IijuE=jZ^9K~u<HKYin&uGAbGouOUj+qtB)Zq)~+w4^`WPk3|2'
    b'MOT@CVs^rz`PHg5TJf_Yu~on<b3n|6V=cgJ1s*Vds~+qO$i5Ulx~Z-wzFeP|Zo#>b8-4wkzhLfxFIB0ZeLAIY3$4|TlfRdRGQe_1'
    b'@vnunTuXc#d7JQ<f-ZaX&_9~@_v%5wb(qRlt<9pbBGAKQ-+oZ8JgOjEv#Aa*;zq6x7a`Kvhj#eu$7b^ytd=Q^W5xGp*xfa!$eckc'
    b'+7Xc>k~pv0L_pzb)4F~K>zsKNX|-f6!AW&ebo3L~9F&xJvuQjtH9A<?#Y%%q(N{BG5{9C4z=LP>$A^D<RL&!Aya(e>`2eu>5<`G_'
    b'zs0X%6x%Tf?bZ`yWzP2R!2G_}%vI_wUZZwfjsG~t21<ESr@-CK5a>NuT06uFGDo0J4|lGWZh$r3RWG>t^GsV))UyO%E}?;*D+LYD'
    b'PrWzQS;p^zYzLI8J0*ordla*T<>k<NOXMGYMs2yaKzA=Ew3R75Z?*M_<E80w>Fn2f?aOd3`jVCv6Y9YWO+NkZGWhqA8eAfdmWL!b'
    b'K~~fNGEP4CK4?_02b!~YG2;pMO=zl&S5>ORy%ljU_!>LG3DdOUsy|cIuyJj&^L97bgm@S3RM>{$dHBUR<fRdk{j}v7{HjR!o`DKG'
    b'2PzjJwD6id&fZM3xm7f&TeIc|>Ht=!E4eOU1Qku$$`x%v`Xi?P@{8Kf_6PD#&yR9m?iZRczEaIew_N7SPtaM`YbQJYc{`(Y?Q|P$'
    b'AhEElB=E8FY49Em?hHxY9|@k#Io}*ca`jtuahpr_=}|Taus)bk+sA{V2tsrr0ZjVc+qQ=+JmVB-O<X?v%iEX0N1{IiK=@Y+kQ*R$'
    b'Y|P{;zsJV;A$X4P6<Y7ltj?iXImBNxzla<hZJ{0X-#8Z3uEQf*P}IIjl!duT)Ezco9$MB(*fuMy_TA*$zTf}!%avN|D4*m;`}=#Y'
    b'X-qb*)@k^v)Lb3ml3L&f(2D;yuCi*VgYxXNeayG(KiqKSo7NXvnEORv=sqp_sdby>TJ5p3F!||s{S@lQ26c`Fd2#6WIOMdf+!&~_'
    b'f`8nBDTi|b9OFq)9)!iU{hrX7>g=WI1lH0lqMoy*-YEHdp%au)sItd97p50k*V%`Vj;#%pl+G5<)ARblXo2zA<?_Z_oh}nuJrw8k'
    b'&QcEjJBOWbcQdbx-##k$%;+H}+m;hf@!eRa^g%cs(9$k9;tF?dnszEP3#j*clLJ!D-K<K&veh(PG+&X{X+3D-=Ve-GWgMlt-swBO'
    b'0VI3cNwc3vt3P)-eLu}U#ViU`iQm)rva@Ks12iIEZ#A&Q3$imZ+&O07rzV#oO>VLYQJI?WrGmx01Ym4!yGN@v_b~S!1qM%=OvxB`'
    b'&O5iEiBhZP?tV2yJ0A%Bs6_xpmvCS~ghM(IF1v79g3wFlyiatlH~TK<D>GPwk<rtMI?7m~{8)kW#t<=gCozoHAtJ|SchT|e-g(+A'
    b'S8TsDI_%$Z)Z)g!-|7j{?!#>;yJA>dtqI9_whunmHeEf6`4(~x--N{Et0~^7vR<pqp5MC$TlArbh+D~*&YctUR?~Y`gqp&jSj;TE'
    b'p3K_-<AfZNzmL5~_WI3#p?s(2C99cLK0ar9AlOw_Amr{17%0%=K;xu1Nf7hNM7st9T9001pUc|B!9aDtFQ1D)Bw5}2z<_t3>vFG<'
    b'%FqWNWgW>LwZx~;En3;w`DuCrYzcaqYjWmFmQn*3D<1j0JwGqzFW(OIGF7rliy)dHk5jXhy-ZKui!*ONZfQ@+We)WY!=JliWpz=^'
    b'%AIQV!)IU^^c<7zi1m8fV++-OSTua!6#ZG=uTD^TR-x^$O{<$HFhz|}%By9BIJ)URx||4%$ET$Zv3)TyDsP3C5fIQyF6#bmbIq?d'
    b'HQ#$tP`j2@1(pn;tc$l+3hU?kUH$Fyn+n8B9quA@Qm>SZ{nhJ;8Nzop%%6-GodldJr4h6>#M-pzeTCxVHoTYl{Z4Cj*kw)9`UCA!'
    b'd>D?Lzkumocjtx3)je}Hn1;jaqMgapi2c>*eG&QuVdF%HI|8_ms4PBRHYZyDu9FOE+(FbmA18MYR=DBmJ=tA(EvX*r%{y)Y<Fcx+'
    b'5nAikmdjck{4saoATRhs*4kMCq|*UqUU`&gsK5MW*pKe3Dee$g=Or;yh8~%!OX(acZWSKgp)r7i&+pgHr|;sRXYOm<JZW_f<3`h7'
    b'wYumr#%bl<puxGk!x1Cm#{Tode*_05>FVOK5<88b4-9bt3#xsKrftUwW~HqwPIVx2PV)(0b>WS7JpxUp(QGZ=*=s`BL~F(6o7?>l'
    b'@b685IzAC{Z{+Ht_5^MIQJ(Nndp+CHuUr>m7wE4lXBYeRnBn5Q`;A`7-p+3uxYiQjZ<;15L#T5jY+s}2UfnTg#}Xb~4@>AMu7Ne^'
    b'?^3)$j)I3~t>^c7M6M<K2&n*ITfSfhh76{UrgKRcIuds0#}C_3<z2ONSud(yt3xqq>&}O@&7f*F&Xd&GPpDme$M79)LT&CRsi<L{'
    b'<33wb*h9kvM~q!WX}-O*tN-Pl@lYgz&bI&GgbOwy^jh~W6keUTe>y-03^wTBJsi}k4SLh|vatwW0n53rW3kqoZ`<A`xu3<q+q)ZX'
    b'nX)mjPeSf8w%_@_ci&ssvKOv5^B|~pZ%olN^lGJVOp>y^dWrVv%XX`?*H6<U-|x568f=_T!wAov#8gYWb$Ksk&t#fdq%^%S35u*`'
    b'Sk3QQ7pz^YO8fXNmHxtN)VA@-*<ub?<?LwV$@Ehie_D9UO?NC|98Z35WtX_}{LT1OXW~ucnT+vs9$Y6hxm43}o7aOQaZ{xO*6wBN'
    b';isBUmUL9QZpm&9PX?YdpP6i352*6tP%^mwu#v*hsV!7TPrS6;V+icH_8NTv51(g#HK}9&<k<7wor_M1sh{MiJ_<;O8lAfrzI<Rn'
    b'cjh^dy*}5xk@#Sb%eZm3c-6$r%R?9Utw+Nif~^r|-c!?j##xQ6Y^-o*MzUQU@@p>^(*DmYc<sAx`s}~aWoI;9{I~Z71P?E_GFjl8'
    b'>kBr<#ybn1{v>z7_L+{3;?7%ui?!3J4?jghKV6}zyOFvRMKj_fFs702Rq6_fco03g=);xR{e7=Kn=P?pYPZT+qu+(@oxd9}6+(6_'
    b'O!W6ezueAK)NL7^3mA1A6HneJV#z9pKLXyp7F2$qd}Ei-Ck?%3_ZF8`Uj@wdT&rZeXWxrA@7lI^`Sn#&X`RY<Z4`pS=7IWS5j952'
    b')&mu{^h>!C-;3^~hOY84HnNDb-Ue23uMfwKoLJdXXYf=`n5{=tvYYS6RE3WKI6a)|>VdltknprtSSq4^HTqiWBA<sR0gg0xQHQ#D'
    b'qw~nwPLoZ%?$z7A(QR}QP+rD3<5-9I<=ZoYOZ^geY4HjrqbGHV#W$U0Pvs2%I?>=St5B12iBj+Demc)+;qt59%-zTn69ui6sWx+C'
    b'00S>fYW4sJEZI9<or4pIF-N{}L^$HF1j7JhP_AyuCw@FVX;WUEZ|je+`<LWupehROcJtES(^J+XHL^D91tsdN|1f~Rv1nnSwLkgG'
    b'zF=$He2?<syOZ);G<AAYxJ^u#;IfW^vqhBLbPY)>r@;i6%Zhd*k-4#)uUn8Br@aAtUaEtM)SV}FFf<1%mqoWDapH}Bnx3<%kU1dL'
    b'j#2jjT|(S`9Jr}olU`o?@ZqfVauTm(j*ib;nR^QIaJi!9SFidyA7Z(ApG}$aD`DF$p>#fW-###%%+%dF0$1p#GZ_wV){6SK-#qq$'
    b'&0oeFQx|_fps~thNqQlPNRv`LrRJ+mCx~-Oi05X(mIo)Y357-SXk6$$`3`ryJ{@8n4L}r%r7Ng2bb;06vlh_B0%&HjJ>!`1_V}BH'
    b'0cI?{Z5y*x85n;FVptn$=w*kH<}jaa8^f0T$$0&}ht0PH-fqnOxa{1YkHKRyfixr7=AO_IGOne{d~q4~yb80^@X?c($Pptc*Hahi'
    b'I={I##dbd;L>f(FzJyBs$7Zdn>o{6I$3yd5t@ecF_58L3(h1H_`2JXUeeSDX5bD**wWaecH%hBX>!!hrCV}==(%WE+I*5TFgYO^&'
    b'Q+kiV?xzFjJ;+9vFDtH9w@K|qJ!aHJsSYWwc@2drvAFwzW|+6b>O-{i#bkJH)U4`KHH&Zyg?N9phkGn$OId4+Hax5uTxuJ{DD8pj'
    b'td3h9FqMtxFGf9Ay`gZJ?kcG2C^-K};zh-1#S`Ha>i)1)d9?lHbGXA+cmF6alH-WC@3Cci00E59nELLo#$q|)bY#0J*{ch!gY9r('
    b'vFnYT9cidTm&WfOUvA{BQQ^F9w^d<wAUk|Ndz~w`ejI>nNw1oyuC%t7WL<{yd-Ea32%}xd@#utXdK5T^eCFxLr7?)%;CBB;|H6!X'
    b'EzRce85n9#XVhzir}y@Udwt_>epy1?DaI^fh~_(uxL`Q_qqVQ`0NEY8SlOLPQzQ((9UoW*sM<n~w5n^8*Y+T1OI{Z=Z=_myqYF#+'
    b'Ecbn^f1RRs+x4=^jxMop=7*z73)8eN!euF48#C_v!pOF`EtU{QGJvA$o7p%l#g)veUe>;+ND(P2(j8lf7OcH?>T7#b(^-h{c5ErV'
    b'vQ^9YW^sN9BlPiITf-gN0Db3I<Cy0sh^PE%=d!PM7w3jE>vb%xLT!mGOG(h~t+Y5VFO1fwQ3sh=h_d#weuQK<Xg~OQGT2q3?&e$D'
    b'VneM>95MBjm7&6T1D7X4;jM=I;LYE2l`E5Kpe{oNyhx?ybb*f-W?Lpk2HH7Xmq{0|kFw1;nwH0Hu?cKP9}AT7gh0lvWXLwg#jF+;'
    b';rB*7t%}mjQSeU2H=+ivGB;{p8+)&~{?nG*`Ugs&hQXuFOKbK7pVIbAvdyE@_tce*oG*iUMGFwgS^dRA3tPh?_b7?r1}UFkP&<mp'
    b'E31Lt#qVsE_5Uz$LI?NuBB`5E8}KyHuS#U+$5XcT{fC%Gbl>s59(?P`m(~fZ7M}&rcktj)lcdI20Pe0&Jg1fF&<T>{Iski|@CPx-'
    b'N0!X)NyK9@!gZU}P3vFr;fy%+Z19LKCKugy%8vA#86oQZPKRV$AC<V}laWup*1Yfd`gvsq!5{Pl*A2*BJWlmctWt`d`h)gcXHWHR'
    b'-rNJ_%V@9=VG;E}CZ_|ov^2YEqr=B76nSnxPDSg!CjWL<DV~0<m4N-q@v7I`K7Cy(8v$`!1R=<W9(>A%VB*O1_@qB83b9{S&d=Cg'
    b'dMwP}%z}{IGI&Z>8{jy4Beo;soU`kc+u2b<2YgH=_M@Tof4`MH^OfvB^ZwrMUAf)qW&^i(r%dj+?lp=-0~(Ia^H$l;Lc@V~y*9*j'
    b'=gU9L(nz{l1kKLS`nkE@E!AAK57T>0PTx2&M%ndkUTi04I$^)g?;T?K>iINXc885tO?LPQx|_Xbwt|hP=bCdI0eJ0ND^fNG&#e(j'
    b'w-K3fI!(RZ#jfX;b-e8Rg{GsRur6P^#F<E%_&7%-I6p<OR%-JAnSOp;Pp1bZ@Vc!h#C5nhq2`5rt*U74HtGV2aB{!BmDqji=*|@A'
    b'%DU*{dv-A<=6=izxA-AG8QD=>S5E}wQ-^)bV{xS?i}IKRH;gy=xcg1%`P0nFjsOam3(eYW>WzTubTy8^bKQidF{?S1alL%y!_&*|'
    b'4X<`qTAQtzUR%#*d3vij4DSEIa&RFmUZc|S8W&$ve`FFSTd%>Tb9=Yha>MX$Kd&lnoTVe&ZY{~G*SOR9#lQ68)osw^zHzJEKO$9$'
    b'ciUeQ7WSIULcJD)N|dqBDV3Te*e%?dYb@Nv@n77=hyEO8!25F4MMM6p24#sGUiQHcM;-Rn51%{jf{t>{ME-M;z@ke3k1&KtMCS9$'
    b'&Kda{-d!t@+hbIA!%UAEyYJ+@-?|+!*gy<b)Cc|Xw7Ql0Q*2s^WPTo)<!I>K{n^ENe|~-DCe%)ir;^I3)Jqq!AWtSa39xAWTCT0('
    b'ndYERfK&sy{FZG*yNKWjf!My09GH3To;KaEBls-R$GY?Ib}21pz@+k+HH;R9X#F+nQrhMA<CP;Lce}>>vos0&0&L5pI6@x6WC8l='
    b'V&}C!e`M6r&15h3ot+v?uRZ><w98G0aH@{~AX}W47IVCbd)m5Re!YpLUo#tgZ=we-*<!0()@%Ln{Jp=vyz)O3=#cfz;#zHo<qW&Z'
    b'l(u{5-bvvv6(;9e<JF#~%HFCphmbp0_{0j`%UaD8#ODw#-W_@u<BQ2SkP27@7M%kmrr}Vh<md8ElfVAnSa^nVCRBEBb3Cu;$~Y!U'
    b'VLQ3#ZRyKeH|FrBYo!{wX<>|a9Sw8Gz~f}J8J8;G4wapWGjnQmx3FrJ5IDK=`UF1;5AWvI4|ZB@IL9^-)_(JPf)}ozPI1?Q;O{hv'
    b'jVygP$?|kTSmtrx_U$UL?B;X5MynhCP8H(P{H}&fS842Rf_k1&A2<vIglR$oa+hEznHr<4Ez+GkT0tLyi?i{sf5T~s&6sg)hyx(6'
    b'Ta>;ig)YzWnt9<Plj^B<d(d2exTAB<tW^ol$D?)2dyr3EY|Y2>*0+LP>-N&*7oO+%-7#6+K0cz}*pN9kh+E^6z`H-qe4%#L$EyES'
    b'qucAfdFtF!X`*&g+-w?Tnkm<|QBXT=&(}8AJ&sq@ta=z>>-q7aY>WHQiTZ$b3Rhk<Nxr@vwLd*%Vc_+7^NqPs)jzksaQ2J6P4S#i'
    b'p^8rEbDq`+m4|tJ<(t9ck=~Ho4q$lTfeP_%LRt?j%^Ae;7e(e-P~2SFj7SbH;(RKFZFESVjEaB})i2U}N_w%G)}U4|a!LQEM-9<E'
    b'K=KJQt+j?H8MLmiHeI~$+wm(4Pv%n<=b7LkJnxpaEwSJm^O-{M{WJzQw;9zt)b`L7dO&l@@S&~J+Z@xAeG9s=&)&-(GpL>PTkAI$'
    b'px!lbzE~5&+umR6^Ti&lor#QC^qBUzOHKVTI3~+Gty>zY$#uVV#QXXpEy>=TGp-G<lYUh0w5mUXQ5CDlTxRt!>`aWg|C~*pYlAAv'
    b'ob>bGxGHy8zdkD@;oX*-{-zO2^EOyzXtlED-I+!V`>6w^Rf81%?lGXu&kxeOpT?#5h7IRK@+%Cc{bjx1)9E`{>Lq}@fC=Xn70;b^'
    b'lFoa7<D~!gnvts+p%^!bT@JaU3iitnjTU<DsS%87|2NNb9!PKNnVMZq8g=Tx;I+GX+?iDFQcs5Llqo$H;IZkHvbbsEYllwj<QN&p'
    b'Y-d#Wx9z+CJBMArxgwjleJS?X&*l4C&TH-2ph&6aaLcuY5|6RtXt~>P=lwLk<Kf;E7k?3}xnjZx(0#q>mGg-qeCX-J!^fFECSKEe'
    b'Rqw4{w+_|xq9;e`@40XZ?Gy`mfL|<E>6cgxqBT3YzwhHE)%$XmzJ*?b-ASNQ695l`9T8!Ex+Ev#K|Q-xhD>OUJghuAOdy^Gv-_ft'
    b'EgRd!i{@s1#<#|!?Oy%GC~Ins8T_lG>eK~y+s;m`RQ>Ta(y$AA-|F#esvT>^dTTF*NqjfBI(_hoq15!(8hvhi_Aw3L{EKd(!V?R4'
    b'<=Ut@_u~@|@HY#=Bsbp+;m`APYV~m|FqSjfH^X643>bfSFV_2!b5+*&(cgckQqfpqojMH?^abpbnzD}N%?K`;x!-e$>T+!y&yU0O'
    b'EK}$rL9W&A00dQhKQGX>;`R;b*DI3g=qX-{+W6J;)9e0Rwl_C3HKplvT3y!V<Yuh$Yd>Xry|=eqw;mWRnjo#d!a%RRo{{Y#3x!*_'
    b'aMv$!PnaCL8^}DAar~Yb+vckrUA%u@RpU&wvzOG_PUNxaxPdihdt>MlHzr_9t60qvC-b2<<Za;Z3Ju_XtxE2_%`sTtU&>S*Swb?p'
    b'A#nEEic|Q~Ad1y=d}^r6QK3Q6az&>5Zu;|cxCx=-5$oATQ3R&qC6pq4<~5)~?{&?1q~x)=YMxrjEWDFlI_LvcyWIOa>SA#y`%!@$'
    b'@=M3vZH*8e$r3k<{LM>OKrNZQ$tqQR?w1euPwy3XbKa~56=Obo$)~@YzZuAF2`HxQUXM#t!dZOn4pf3_$D}u>+aC2el%*7CHE$<<'
    b'6|Yx<+!_U8(-yZw>zLa5nJTgaS;s8KIe@~w4FK40E<oIKPP2`%1HX24?2R77=_Z`r=<;bKVHSVn;c69o!UL{8Ml<VLtDqg{H7qdz'
    b'-##|n#_ch`kEB2D^%b?2a)#=yV5FgN10x^)PJnOxdgK1IloijSj}ai=nAxnAdL5u+Uc{DeZVYam2j*i}+2wyx$M#|)U@(1ytOj%_'
    b'VjC}NSm#|>?9tu)e1*5mgFETJXft+r7-=`FFo&W#|9rK4{KqT%-y0G=GID;z-$(pl=wDkP_K;NHPMNu(Am(v2UB?@19%HgO6Sd4O'
    b'_YY_+w4!b7&;9ug75=CLdR|sh?)9M@XP_joiHAiAuXxWVziu^u82eRD1hee)``lTJAcR|ARJYu^=Ag}M8FDXmfd)(7hy5fTgO75P'
    b'-|A~^H|zT-nDu6>!KujWw4|3AX*zshBD?_s$KMwtOhx2%Z-#7-y72ShQq^FTECJ&H0o$V5xU?YZdfBG=iB}+C>_G?xZ9hFBEPv!9'
    b'p@2Xk)1ki52hbgf%j{m{m7;u!^&K^t9fDS?RwvAB<JmsbL(<z0jM-8f{`xBQRr*?PR=&E#DmG%2Zna_>m(P!J{H_R;L0^_&4bh%C'
    b'lzkBL^+(3nWTU>$^>=m*j<oJ&ZMAmazh0a5j9th3_Aq!q!hM_h+(v`F7~iBW_tW$aTyAWR#(8ky|2{?N6s0s1^;JaPg?c_~SyX?A'
    b'NTq#QR02kgPTSMW(x`2#%#gS`fqkpDb1$K7yQDq01O1pPEL(zZ>-7g+S8RQNcO~aH<8xV-v2<!^$PORKcPE*D^jY+g#2FU}_Nzrg'
    b'w`g-7A(a6=;SIY}A*HIvcJ4c>_v)m%@$g9w!#@2_2Iz=8Mz1Y;$sI1Qu!WSjZ~Zhj%*k)&v9xN*^VS0f*L<frz&Z}idqIx4bu_QX'
    b'ng=Ybjig>r%Sd{W)Bcoxw>vuM-ka>j%8oly94Up6;(5;Z>W6))Ul(7(<Xiye-!~Sg2eMTR<lk?BIj0?`RdtzNQgG-PW&Vr-q8i$R'
    b'{sX(<vjlK(tC6JRkvEZVro2i0Bi0bj;!v8ew_T_$jxSnvW54z4Y9X-7H~@yu<5mr-Yx8a`$qdPUngctEx8^(wzRd@66K8Z}4i~DW'
    b'#u^?lxGg<9yLj|vut@oQuWQY~#k=LTpyz64EJvUu^%jgcSiI-Ca!S$2h_rIWrPpRZTWG+rTfS`L=k@>9vNw}Hy@kQ_P%0g!i`Jw3'
    b'%m>_*Jg$XJlG8NMpbd2P>@Kuh`a<Cn;URheCyVdf=_JUR+Mo6Q3n_^%__{|xcAJjhU$4RlW>6?aGl9RoU+;lnPQ|g=Sa|S}ir4J?'
    b'`CRT#_>oOtiyF!dZ^nh6=p*Hgcdk`i8Dbv<yU_aWWdJK>+H2OfQ*>NJn~QQ~iCDoocR_x=tY6ft4PF(Zc?bnRjc5uM&oAB&BrxED'
    b'&UwqTJHqHRbk8y$UgE+CUs+)4b=5^X&$?^Wsmn8ElPVBZ2bfpYVj)8x=Cwcd&D;F7R?Oz*(>X!2Xv(5q-g|Z1d`0`6`PaH$&EQi@'
    b'YW`(R4$(i>X7`$ja%FOsFLY(o{;=y-gX#3?)0^IH3a1He`5BK8>N!2R>7Z(t?)Lr<&d1k>ZMM*omDDBF70^@IaJ;%I^?!N!z?dT&'
    b'AuDTQi;gzrw8zq31D`;mdwrdU{(G;91$@u?%f#hOGCAbowVOQ^EObcl{=%}oEZtvsV&PQ$+jU}tKnp0Z+z5NCp!ggi(t$;Om@S<2'
    b'3-BT|fXi!`9Rgh39n_O-N~>FAjgGyVqvj$GjsRS@2CEd?t!^t~c-VDwf645lXb#ysV^0&oLs_0N%&J=F&<2Wj=<RJw+Nb`#*1!JS'
    b'Z~l1(8mQl+A;M+ZegM5>{AS(o=WsgyF2;2n0RVmQw0XWVs2;%Ex_jN;C(`HriYMJ-`nLTrPOAZP>9*|JY<?MFn=9PBc6apa*aRxK'
    b'Df#P5nZ-n8K_UKbgDZ?UWmE~!Mz?X+;SzG#%fwWk*UK#%qU~=*+kN9tK?zq}+pH^cUS_-RF00VD=RMw|{j^m`Gtxr>uGbgUhR_SJ'
    b'ZwcOQe?De59;FTUU~|ewnR5<dk_TFOGJC1~j_z*&3DSXRHkZYEa4<K-#MKA<LA$R>|C>x}uFy+(25(+o=QDlW$+;%IrqZj@TdmJ0'
    b'OC7J^{k*;T_4f*8?KQHih-2}31f+v()zo!oy$FWN$gV-j4Y;*p&bmz|hxTzjy+4K-cp<NDYrhx>5#F#%h!Ql9l+s?-b2)<l7!@~0'
    b'``{JEhM&?OW+gj6ovr_V#{&hjC-2&#pM`&?8A8s}e#s@u6!~OYhYdE|$XhB~v}@{ScXVTL1!w_V1i&8-kdg1J5>1)XB;6ks%BhQt'
    b'*1YG{(;z&zym$5{)(HLU?=6+qBb!0l+wMQ-RJ8u#wz76A3)L|rPB7rI^`_YfI1%mC2RhS=@kG>O;s-sRJvQoC>T>1l_+Gh8C0A=-'
    b'Z`*fGgwDj~*rV%R(u`&`=xqITw*7~hZ`!W^?BQ_tUIR{E+reK#!)i%mOXw-`F6wyg&lfDsL0^!~zYNw@^eu0#QFO{o#;p@Dcn{Ot'
    b'0dK*BmO#{+mCo?WotP_5;q$#5H6Fhj{ix&b&m6VBY|E1?Qc_PCupgfMTV*FVE+_zlum9FKo{v)wnr(^Es$ukwIHY-J_+uf+J3g=J'
    b'j&vE>v)~i8MBK+Cxtc;Z<0Yy%()-R_<?!=M$!79cnPqh?>|c!Hech181PcdA1-#J>UL0MqU@*wqKHeTk{Lv8@hTRQo@DT?$`{Y_`'
    b'*Uf5av~{y-m%q<e6&(kbAT{voeZ|2~x>|T_@UJ&DspYFpdDd?>{0nq?eX(u0)d$v+E(led;%-;P`-+rtICJdl`x_OS7=L}1_}FKh'
    b'<96A)viW+yTRo1I-k`R6T`^6~3Ui0onWlI`hvAd^-DN3xF`HApKAhL<@dd)1=0c|N&8_sZP<`OcwIu1_mw{FpmTf&l7MstOaq5@m'
    b'(DqaX7mpIgePBFrOt;HK^<y8$1+89}I^LC*s#(1ZHsK$yOncr0&^KpBA=E_N<I`*QG>Fk-0?RF*YJTXiyBRR`XI(ihD|I%9RWx~F'
    b'iMK_Vy6dhIcHHT8d%a#HUuP_5QY|=f8~WJcNQIp8-I?^Df8Ob7d2rqW!e@G(z5U5_Ive!|qib9(*sI+-UhAT(A^pkrr9n&|jQg&N'
    b'^^oKe;UnF;po3m)tx(f6wlqPlsm=5x<Wu#~ckw7EGS_|W+Jc||Fq;iz)!C-odg@PN=K;-Ir#bF$+geBKE@|>%zOxH(T%G&99`cv7'
    b'yyMZwNy(zpzYp?8=Wcb{8<DIjde1N5FJC)Q!V1xWOc#Q$Tb-G8=HBw>9dT6T$O(*jp>Jx_z6oY{KLmPAJOUqF<4L@0UL=vkLN&J`'
    b';rO#-<ub}_7<iT=fI-6cH^AC3Pv71m&RXvSI6Pe%EZe!FVh^nWgU!BiG=BH1@}2|JDEe>Xb(;}3lXlOO7K-6O=V^O|wv-$2>@@D2'
    b'wsAeVwhcIq7+>q#b^C$~!*U?x<<;%5&s_!aLorO}#^_S{LoiQv&igyGeUL3?{?mxa-n};i_4v)&J?cZdy(diJQ_+3CYV^c+Z|-Bx'
    b'zQ<Gu^Yc}d&pJiW*p&K5x${bz;9f1iHvyZ^pP<t4*ky20eewEnH{-`E>ty>cRt2xqpT`|B86W%n_66yBRv)XoT__uATk#tNbNOt5'
    b'wBDRd9<_wC6NaJ>?B(0rfNKUG1u=ctaFtT0KDm=4BVAvH(=@NWuGi0FpdnT;u|DrH%UipDzWVqx_uDvdxKFVr>V%wBs%;;mW~cWG'
    b'pqgAd(7WmqxVM@9<<I~&O32LDs~1ph5(s*KG)OK#?6>XvEL#HK!Cbz}wznXdV^9mV<QvS|V3C18Y{L%*vQNCL$Pg-B?j5_i_(GlM'
    b't4%<n&ozZ9=*c8kCPIFa5zne#c{XQ3TGs5HSY36_cY9F4eI*A+AoAG9nfqueFA6?R@nxH>!Q<|B*ggOHh(s1{1OYy)thfD3Yk|KW'
    b'&lBsG-=D0J%&)|Gl9p|LpKa61Bi&V$tag^|15c{shP!SBL-#XZU8L&qGx*dFrEaO}47Yx-c5ht8OVLEXy`v2Ma*B9GNAAcss-1kh'
    b'nj8GK4#9o5?Cde{(;rn!t;@1@p)I3TZ9t#BT=2#w75aJjbglf*nMjR0gDmj6zHPLIuLsp@rdfV(u<hDBpD<^tkBN(49kyw8!|&<-'
    b'Bv^Mk#?sMIdlJ@ehn%a)=vHm=2+-ZMLLH7SJ18{wX6Z<iOKM|BQD!#t&PUvi&&k4Fw&e#wXt>|G-fV9#G7V$<g@+l_Z0vt$zV_~9'
    b'lh%D_JiP?^I8vxc3eel`)yqgNa|p!Yj&EGi<7_Qnp5*k<MFfVT)<mak)7QQBHX8v#?8+o<V4LkA9nWWJbLqU|126-LZ8p01=-&*&'
    b't*>1UqvR7;N#A@nYr>$gx$+I!-{f&w<(Ez9#ZlU{`b41TaI?QMr%ASZey&?62E96;MC6X5*yg6$m=A%m>8?sR;w+=~Q^MIn(LV!|'
    b'?GH!U`6%+jbNfCyKwmW+er=RUtH{<**PS6Zp;?HDJIMGy!3knoY%`j%v#~bZa&@hzL5Wcwd>4(*oV%K8SV$$f6S26VQDyq9F#y%r'
    b'iriHBx6ilra$`00l1nd}Xua)aJldCTE_bdFS7~L%+0csi<Q<gPfqJ$&=k~^JlHUz#f{);|J62lvJut}nD5g~ZzyJcQKihT){y~;3'
    b'IDZLbJn#SZ2Ij#nA)8w#NO2QAmgYwuV|S7D_5QNdShnI-H$Aiu*Hbm16#tq4pS$q($(qJ21N-uAY^M=N9ZksZ676NdJ1q?->qLjY'
    b'PSx93sE4BQkllaJwOjBV%b6*I&Cb)S`{8@45>~MFDljrBH=OFA4s0ns+c5uiT^5RW&+_^!<}V-rP(M6M^>^*X&%7`#HezkUHO@~v'
    b'qfMX~jdzDJ>&6E9!vNdW<?ya+YXIv5%O}-aWYQ6T4HT_@9k(-3E^~(pTCg7m|BU)|uw9-q?;^gDOp|d^85KbPUXrMEo|{;xpUz2U'
    b'QKz>s`s3Pp4c8nN>Ja}tOrCAQQ*$KVbBGwwQ>(eiJ#Gg#DeRAQ;l1OgLbYx$sDfbZ(QuQm;$CI<@|+->($mp0E@lQtBT^3YijFvx'
    b'OKN=<%b>jXSPtDjt2P?lA2)9=xQ%bC_>26@vx__M8u)gn1S1exTxVs!f|!fh=|Run#&eJ)ms?!D4uMy_##s-aJ{&FsSwgBZyIyO6'
    b'zt;MsvBnpDF=xVCYEIiX#oA=QeF1cP$CngCw$yceaFoFi9`5hegI^DA@HFq*OZgPdsZCKWqH}5J!$zZ8uX3Tf$lE(36$N~gCpj4g'
    b'H;@Ae^5Na*3Wtl$`FOS(-{=i|O5<PM0h(ol@`!KWE3~kfv`XU<jimmwazk1w$4iM>$bAU&Yb97}I`sN5_8<5`+;}XgFY!&}P6DJm'
    b'&CA{dEt_=8gQv^xEi9SO374A2sTfqV;@8_#-LYwfyi?Xdpfx+Fi|3D3Gr)}<XMf=gn0TFUrmMri@0iEN&U#G?Kg<*BB*xtua_le^'
    b'J8tiVHHN1T2JViCi?l*}CrgB!Eh`fKRL5%BKQFlZe6a|vS1X=3nTg*zy6au<d2yqQu6ymp(0*~#@vXX0QD=G`jc%0$-?ZjMT^43>'
    b'>cgW;JIrCSEON5hNZ?3sK3acS5Pu(6K6oy!Bjx_9o39hg>F^~NJl&z=>~eK|t*c#m=zFjZ9gXC<hR}WK4dhN8g+W?9;x#vn^t0OP'
    b'v|BY{5eQX2ZcxK(v3*E2@U@$~>*1>w((*b*Mt8bn$>$$;@UvYJWK2qv%w|ciloBSi+qBp-`){KGb|^v}K!zh_s0*2$zbsJR*qc-1'
    b'HF__0baoY?&+Jgk|JX)v;erZ&7sJJ-54xS@7E#oDK8)I}=}&`QymwNQ?RElW*otEhlVHxEBnhKBo84jb$XYbqwR88H->T4abzIH4'
    b')dT9SCWr5esHB;PvukecJ=JZcHf1+)PLRY`JJoiK)i~qhapU>bf4WT^;0`%=%G#5h6}OvV$bT$`oE-IXox<ZYXtDdg+{(K%Gye7$'
    b'CnwY{P=MSI8M`F;ZTk-?Fu>ZQ*Mt<rllbyzaGWlQ&}On(*3U4}9h5#l4@m)h@*q4Wz}wOe4{&)p#SEzJ055bhimu#R)?o89XR?yH'
    b'Z)ShtyS2=Ym3<?!TGflYe4^dMIJzSzar${XwDLvdW3|+QlX5&Rv`bCdS$gZYyJ|R|f6uMnVcSQH9rU%|&n>aH=EKkM96_@I%tLBM'
    b'npp|5Rf`?S2L}`ekJ?Bss*CZ$4^RDhX<Vm4znv<LlusJ-V)|OdhjU|xzFb9u_y<b->$j;sM`Zg`wM&DREQ#%F#;(>c!)$JZ=L%9j'
    b'=jy8$jMk6*uxeIH^Zh+t_qeY%u`5S(%eDCP;+ER?5EGH(WD;eVIT-u_yJJkDtuP_<xwZSv_&oa7q~0=RtRHsa?l;Iq?a8j;A(7F-'
    b'B$jk>k}`ws&b~R$*-Ew>JyfU@U2TxFEnLV%7o158dXvE8w#s0e>H{7{(*uJq;K_e}v@?7zUMoL5ua!dTa)yJ5P~N21rkeD9=oVG>'
    b';_A+j1jmyiJonsM{t?#m?&Bp{<js$LetnAcN-#Sld!iei;uz>IIO9{aw)bE>!4BW&`1~A)BmV^Ozgl*8HeMzrd|r)<(^)G|!|l>n'
    b'x0EI3$}6G$pt9l9PQF=D-P--WIK3Z+ePg<#tyUxDbVEF|ZP#K3=SMQ(akt}UPV+sR@%I&0w)Cw1$#5|F-DR$rqD!YIkH=s@nH2a?'
    b'pDX><Gv0Vlu!!!(p&yiZ%Kdq`t?GyP7}|e?$TTjfl#XjPztW9LO*n35@~Csvw_JA9A4=VOOlQ=2%f9v!${l{YtMt;=H{i^>0?uy0'
    b'=A9ESv>$A{oUcAqZx{_+bzUgtxO+;-HeQyzx&woAn4GDT=!Fj^_x(^p?5wywzM4=+S0BCpTv7GV>g4xg;--Cm|8GW>h5o+4%xk1`'
    b'Mgm3*(Nq%(`nGKSHaZY{sKj*-b#<!~d$7N)WVdoGHm+*EDWAwByiD$u{oYx$7(K$ao9fd%v9^>pUe$NMbfbz{4x?sC{bB6QZKFT?'
    b'=LXZNL+-vqndUpRN2a7c^R(;3<Bh<zAK?L;a<);gsgrL*8`*!)H!sibI`;>^t5>oGzXVMSWNM-!=R{7PLC8ff#6@#_fob`#7t5>+'
    b'tCg~tp~GTn2<R0@o*3~$?Qt{VERX%vt>QB8o+AFe8#sp>yY4SScw6Kc+)hk7FR|I=y~V0gffj>7-!_n4&bIq~NzHb?gvmA~OFy1c'
    b'tY_&TqA??}!k4-DJbLN#8{VyX*VhYJQE6>|v1G(|{ra#-W`hI4c5Eq&AdGXL&&uXb<sBd3)4WOE<%A1v?A?^al<tK{3EuxjZ3w*m'
    b'YKZprLH0CqwRkdIZ@p{egh*f?udV+<Bwc*S>q|Tt+wfvmEr-zP3|B@xEoS<y6E}`NjIZR{+GM$hBDxW@QuIw;riy%Y-(~4v+y#n9'
    b'3CVs~l$DU__nfxoOaslpO2hffIV<5^smwN|sNSL$Z2E#;?{M9&Z4F%V?%cTYnwGd$Ljl4|sloauOF0Is&S<DI>;O5dIMZj;izoPa'
    b'Li7^s+WGY@C*ZgrtL}g!k5A5)F+V_~?xkEmRN8p%{xOgkaq-zOB8)kxuAF>SO`m8uIQM#QifM&V`{ChTW3a{mD)M_(%3i>zw|kJW'
    b'ZI?r9e;;PZ?;Pq*b*Ge6<l6`zPyZ3E5ook-$c(vAqOPEocJZwj*fq+3_^h_}T4}Y^edhW|s()V#*1(XeQUt>toIFOS@I9@OM`?6-'
    b'A&BED4Ny7uwe0@$opTMFt-@{{46sUL$lM;9Ox8P-Z+G>SM#oDwA9a+VSw=_e9E%<G1Ho##1a61T$T<^>9rv<{`)l_HN1d$;A28S*'
    b'Z=>P3ebL-!(|&70ZDjp)n}!Wtvm2?cz~sbs<PzGNEEul4pD*fp^-kf_9_H8g)d5&$Rvk2SmAyI$I!5?pLE-#?QqU`QXal9r^RY7l'
    b'&^-$F@O2~GeA~}rI#$lTf&6=i$(7vTXVzc7^kL_-Cmgz2z>n{~(od7pP7Q?_i27_a89(R2`E}03m;fK(1gW@M(Az1y!S3*B-8+M='
    b'e=rIn7a2*OIqh{sIGd;{G*vMk5&!m#T<qgI??Mx2qL<CbFn7!A4Xkna%TKJn==b6I0Qx+nP&|iGt<S^60!pY^@3TzsMSd?w!`_u`'
    b'9A8s$Xs*MsRe|2aIt#6D=4XFDP3b%Lo4YaZw++29{g`-l*UjhO{d>2%MH7%RMW)Jsf8#dik|7LTQL8=}RQ!Ht&XwuJH`9KXKF6Ex'
    b'fCmU1Zimc+-#>dqNn*9`!)6hnnNMGWaJ&55zr4KNlxuyxF?-`nCX^Miy9{@S%|%j5z12tkhUBL_Jhx5yRa?37s764Xq@Sf=+f&+U'
    b'qdr66aIGI0R>0N>i7XW(FdGK)jQz@k=r|ka1YLeP1!ubT*&Pd!cd<|WLot{RsmH>>80k<uo+CDy!34H;4^t2P(1kji^e&VC7W&pb'
    b'>8^E2TE;<fL+?VCGUt`aDKxt7Ofs?^=A3g`hcx-I{)YkjgTBM~z5My`)lH>b8Mdv}X;J+H9@gvq%vo!y+<{@FuEy}f)hZg$(HHfj'
    b'sy3EIyk54CP`PLk-G1M$v+tmV<y)jqX=Sl`VIS+4v#B`y-#bLfZg7o#84p|9uzn>3b1X>ET@CaevONR-HfbWmu@y0IE-qaS?^c{^'
    b'^*S0+;2WtpYiHfs_9vZAsIShVDAtg)RpjnbR{ihhXq&z3JE4ENjWjoC3AE}oIasB%kN}e55c?+~mB-SAx%DDG@4SkaGCvx|N>Rt!'
    b'AERxe`{Pn2%LApN=;ts9E5KU%A5mA@eJ&S8KT9iGVOgt?v?$U*hBVONg-|rgP>Bqm{rNp_{9k#8y62v|_de(BYb&R18^qLZw~Ft5'
    b'<l9~3U$lLL6`1;WH#aYR3X{7ElGvDPRT9Y0%kG+O_w?vktGq_@-Ywr>X9jc|&!kTM>&qh1o-__G5|rx?i(KaisD)zhitJZ+O{Iby'
    b'*g!*frDd-G<nHpwEr0razbAtI%?EGZ?EUGTj~`_?kY-!y;MnXbeK^7>ZBj@F7RYNfJ`0u4n`^F2Z6USv$aT~mS;NJ2*u)4Ux3T?p'
    b'ha-|;u*G-CW&@tS30&#<^ZIBPxT#<Iua2u29Z!u)i0)?sNe*F)cM_9&Cf<>O%NGtE<zF&uH7j@X8UwI0^w(2$-RydClhJ$aNWV0|'
    b'O4uZen2t@MHt;y(Z*N75tn|~P!oeW7Kx&RV!t`|SLAB7E62%AMR*)iih&Kb&8=-9amjnEy!kEOAqqdP)?mn1=dC}aK<__CSy;714'
    b'wMk<bFKhh55bsfJv}GlmguPemSGy_b2oJaI#34auv$m+~WrAd_RS5l&86;Yb4|s8A1?h;^l$5SkKf?qshs1TYY-`O+ufLCAR9Xa}'
    b')6I|fOpfU~z#FH87MXkC-ug!*h527y&l`?nf<JBsDed@WS)cc-ShiWcLSW0ytOX=Q-tzG^=-T?Fq_cK^A~~ys+*tP~aEjmd>MElR'
    b'O5B*$^9@g)#z_X$=l2n;XUbFPLQeKQc;{b^dYCK5pMOG&TyTwZ43uS@r!cx!KUrF5eaPVO3ZIgGZw<UVD{)(ybjOobxc204m%lZ0'
    b'Eu?ncN7ooX>SH%5l=Av$)s(}dB(ov6xL@Wt_Uqr^2B6abFL1Xg*OM;4Jy-Q1Dxv_lAt;5Jm!^{75tk_y&HYAwRX*JGVe&=<wJkJ<'
    b'K>MZ>$i&)d*1X!A48k?qliDc0Z@}@s)Zh+y#*g>w-<>8+?^699;>{K{Vp>@&_mxQ|@qh2Jt$HgVQIq*?5RN=m9kN8{u+E`WVHfnd'
    b'3#xl_+&!_QE1}eThqyzVJ*GstK~(;(N84gl8f2D}bx3vg!-p}Xrru_%&EHpeL1mrcsd8-7>t}tZ&u*~q^GgPIWrWmkZ78(>N`Ix2'
    b'sIJgV9`TO~nK^CY7T*``9&_^m$*Gx02T)!M4`v${k=kqJv-{~A)qBwxTwL<$0vHGtRD6q1Z881(_~_`8cAl>lnVsEiyYz8`^OgE*'
    b'UHl;e#vByeuElL<f2?9`A0u!UwG&G{w2FMOZcS=0z)u@xu|A)&zq!%;$$Par*vogLir89#BlA0`9hk|af!L2r^rgC<);^R4dC}s>'
    b'*$D0!Gkz;ztsOEOa(Sn(>2K~UcyR-n^yLL@s%J`SYU=<nd#h|VWG}6Mv+bO|&1v>xae%4lO(~vuQzfG;QS=q|^U>N1YsR(K(Q@~B'
    b'b$ZimvVQhHO8+rn(4e!DdsL`@9zo^Sd&>T(x=TPq<Wl;+cyBYAF0Tw#u-`xK5C+V`eFj%^_H2C14*unpkgTpp^AlG-1T|rHe>G`_'
    b'^?@p_4J*UFiL>nVTE4v+gPU|I`G(!iCfLx%o|8uVUinV&g-~9-hOxlhi#dZj^z_%i5fF8Zw}2ikJk|Ghd&^I>PC(e>qwUJzy8VRr'
    b'u^kA^O}mXzb~5zSRNI$D>4I-ck+5bv=w1}GNKsB9z%`-@p*=_hCSiTMOM}$)#$)gB^TooH`WSjNAQF~3Ta?09^ZgcPV3v>0J-1Jh'
    b'CKhNTaz26ObL)Ls_V^O=aMHMK9fof%2l_R&#K<sCuHN7Inrb&Yx-YwXqI(tRb&OIr65srJV-C<+JG$8w+6vKbhkp1fHns9N@urqE'
    b'(a-(+sLs`T%S`|r%Tx27#Gm$1*qk=k<NCUh_tB==i-eInStjvhZ2B|htkc76au2m))U;m9-68nZ+8XT9fY9X?N%dFx^X^^%cR6u~'
    b'#tfH`xp%oHXR%iSugmoo%+GlRYI;{~%nTJ=8U{;W4ZY;5M|TV1PiK_K)a#(n98MFs;Hw>vjode0Fa7!|jigguFnX<1!<MFJq}IDM'
    b'<T{J}H3t?t`MPi-dapUX+G~D_yh1M)O}KOYeoO7${K>$lc$q+GEl^hr6q@(GA8q_vSJW}^W{l`km226DZ~uDd{?7^c^iby_YZ)H4'
    b'jpR@xdcr_S>+hB8&GuyJsI#G)<7howv*YDhHGrUzHm^N!N8-I_aR>J+)%enlcd0S#s46BrGmB{C8?xTL`9=C_|FjhU=`Jt9JDC~r'
    b'2H35o7NR!RrC7kJTQDTwSQ{T4_V%oClggF#qrwIHrR32kYO!D2EtgEw%z}~T<IuY4j{91uR|I~HsI|FCX_%i>ZfL*$)1v~Ub`Bid'
    b'g`GW{(M6;WvJVc9N9CjK(I9uJx(~e!dGGY~vL{s=*sDft<j?jS5|rMwzxmd0J9kJ8chIbo4$&@iDrz-s+w-rrP9Nqgox$TbThW_@'
    b'P-V0is{G?MT%tT<yg%wAfr_|#i)7AWWitSS$)WTb+Nnz{*{^FYX5S<_YTDy<z&LC6mRVCP>`@TzpybVh;Cs?h%zoq2Idwr#&3<z?'
    b'5RjfY@HSmoWgMg_wlY23ckjcMf98A|Pj1Y2d$)UBb9aR{cRy^+TDu7i$;9r7H$Zoz)5MS{&#SL#p3~SyDotghwU#b6iicsnr4sM*'
    b'KR<Kvyn6c{);(l`MMj#ePetQtl-qQOHXHW|R=8b(A2y#i%fV`O0C2I%exoP1K`9NH$!gGgbpp6c_WDt|I+E)(onf-ou>rY4Wl-eB'
    b'Ju*(e{Y9G}5`!kd^u21zx5uPuZf*FJUZ_o5;f?Kaw9NKpwEg6Iokt#zmLf3j;`f~*KE0r%is86?DXWxn;+C|qPemtOG{~Mtrn`Y$'
    b'zMlKiCawO{9PGYQyT=_k=TR@7RrjYQ#5`B<xZ=1ylbWd~3BgwHccy-LI~rGxBx#Vn&ykrD48IVmGNBA5q`&*vhu3<L9l8qj?l-Td'
    b'+mnduu0ip~)vr%49scpese?Rs=o`8@?H+J_*PLWMpRBgQY@!aP2e6{Ua46m<M|FLhV~E`+Mw2OZ0=DO1oOe+5WWH{j`4^h?fi3_i'
    b'^5@XU=1qCl(prlRC|>`~_~0Hs=xU8e{Q8JfTD@Of#;9J0MHin<E$p;;u^d-JfvkhwY-l!u<OBH;S-QMicIP$YbCT({F|@!h&d`?w'
    b';=fWlWGiYvnbPd+@06*9zh04Z#Yg8J-aByNq*Lw>=KAFeZk*Q(p0-v|VI8~RA9jt6s8J{Wu<)Cuh-yF8_jB_;e5spAUeX{jO#V)w'
    b'@}?~}Gf3Idfd?#ZH`G*{x8r2Y{MPI0*j?WpE`T5(-M-wJz5Y?;@K$XO*dPmtN{{?D^VA}zRS&p9{Sn3+n=f9?ACXcD=eb#u{|@32'
    b'$PmrH)He1XQ;M_&_M?$L)tjx1SX!#TIxL<9_bZAl9bq*;U|)JDwU(yU1U_=vIyJiZ?QO_4#Re|Or1MNktbaE7_8%c9(z}_?=6846'
    b'C&-CUh4rrxZeFbmFn(uuvcy1zJ~yuAtQh=iQfs7HQ6l---9QvKdpdtR!ad*J&I=@Z^>q4&Cg<_^bte;I^1#n|Eg+V?c^ThCbNGAj'
    b'yzFJpR(2&_T-vAov~`if4_1Bn^jg{A<{w@rsaN>JhpBX`08p*E>vR>pJpu2=rJaq7+Gr(iG-(XX=N%+I@-|G+EW^p=I~LI6_O8Fa'
    b'Ig1S@O~q3)c6hPv6$Mb(uvqWY6&pR0ig`S1ygzy<i(j7Kv~}!0Z{>HDzw<5R>C_K1rdQc|dV7Do8TWWUv$f)+_vZ*WDiQjX%&1Mb'
    b'PUCF1bgy%mxUx5uPPShQA7NA!!5NN&@i9QQc#o8}^`5K%zxhgno8G<zbBd;fyng&e9Mt(EgC45jg-R7`_1W7mMh-ibSsDxpd|E}k'
    b'1BE`SnSZYCUMdRp*TfT=h=90Rir6rL%8ydD1h%%N99}jy&_gTz_!q!gkD`gyP@&!U!fttOPp+71K91gTtslp`VjsufhiFZ2Lt#Gr'
    b'+!cSCjb6jt)h~tCT<KkY@U<}I-aK9JE_EC%!xHgr?Ru97EdkGlmkh<9&bG)u_5HXumexDs+Cvu<(Rj>_ICZN}sbXq<<M@P;a3LZM'
    b'<nIZPfX*!S1KYu)Ju^!Dm0dRgz3G)Y_xFY#`64vxl+FZoC^}GiE-kuVZLs+DIp7lXocS1+zS|omoL^6F8`SIfeg(fRDUDra-2icg'
    b'060BEAq(h9={%?G`Q_Al$W9(W&f(4xm1n0ZNG4$Fj|AT6dR4hooISn$v9W75o&UH)d;%kjCqA51TF%}L-12G%w}D<$Z6vMDmdMU>'
    b'g+kMzK}ZY|EsRsq+gv(UwlbX62ut);RUk_USbaXNp?}Gx(s(gH%_@~o+5wg<Pt#fdH^<?W>tz9mD5J$UfQ453j^;dB-gWn{E%#Q?'
    b'cs(D>&64BlqV~*NTt2BI>bYvT{{4uF0nnnVMg2yj3*}tqciF4842W&H_UiN%Cguess1T)Jp7$=>po(tW6PkoxM?C}Et+Hbvls&=2'
    b'(Q3pFc)_UpgPxwA_%iRbBX&^jD<w2`vxoj(nPng^saOJ&IZ145?h`1JQ;P=i?Fjg|p-(}L^oMO`uQd$|NS%62N}gZ!xLS4Ob~lK6'
    b'S5-ARbg^BqW}EvPj-QCMNm*C4g2wN(-kdKx)4u??)TRk$(!ARqrj^mOw+}}?NPPY3I!inE@#$UE|IL8w&(4XM(@P39=AGxcm`AA5'
    b'qxJ2IBCw8_x_P1th~tZ2vZ*!3Liv4F->_d=oVx7x+`RbOcD1zUB`)JUm}F~|d`bIp+dF&un#`X67m9zgW|&KM!#~)!I=k)V^t*k0'
    b'F5l5Dwtdc?e-6F+^48iZ9l#S1Z71R{5C^x|`vI8GBZFTqwQlFu45r3intsR^`msDOB|dquJToNoN6?YJ83sR2q;Cl3at3&+nD&%f'
    b'q&u0Bt%N(^8PD%)aBQNlAiS`l;Iugw=*)+uliMIg1H(#3pyTP?2D0fXu-jCuV*FWOcs>o^jcLA?focrf`{oAO{Q9x;*-RN`8v|F3'
    b'Icy*|!$2a9NUQVe@M*vEV1j^rVbNS*b_N@6o-W+-r+7SfW2Sm%dGh$VdKI-T*mJFWyAGcBg_wPJ<HdE>9mT<V)}G<e@2nhWRxPNI'
    b'c|};%fc<DbpYF@6Bh~t<5_KL3cHv**88Xri?C6usui&``PX%yIjQ2bc`;gKs8Rz0Y|6_aGR(mEp_IzEc%tA(CZDt>DU26^f_*Y4J'
    b'(|(F>$X-!_Sr}bF$mEaeHj&XQTkm?wHcXCmtMlA8<TumRR}DKSnq;^4DGom7lk62L2(z|~1WWpRs0pG0_GWuuI%(c}^1IEla~S?~'
    b'oBB+T>cP(X2#Q>h^I&h-RqdMoCC-_!=!(SQZ#!i~EARD;MryPOoNMjKPwB8uPR4V4IfS=zv&HnSNkdKtluSqDdB4MNN<Z*4#L+My'
    b'YyWaD9`-*HJ05MPH`m{r>Fp7Ka7a8Ps>J};zs-{Y(BOV9dWRPbOzjTd!+6Zn_fxg3^n~5X$C^C6x@@y=EKGyDLWMVfDXy}5KwWlR'
    b'#Vmc~pAOK-Zcw*=v5uJkeolAx3Mh(t|4`u^(3<e)QR@zrqjCoJ7f$QByZ;3kspQMY!0XD7UCHE1O+TE}7jxvp7nK>aVC!aSdI8P*'
    b'nh+55JE*lvzrEZwXy@{{mCELp)?0Sn+!tJpUsh{^YNOMvU$s-b@!{?@&b<)FKJ&;A@~l5)!R6=so?i#uS19Rml+8X+`rJpJg(B^@'
    b'VK3)KQhvdcv1-qMSoG)~-rD+ln>5$lYem1LC0<S6XEYG24@?uw<Bhoe7~^q}kNd+-*O}$?b{)JgMZ$)JJ~Ep|&==&hw|iAwLtVY5'
    b'fU|j^-ix6kt`uW0jlcc;0TN4hNu;&<-wouj^^c{?6;!}P1g(<-34@r#TEVSx+vfvFyL-#|tW$%q`3*HHCF3v}Vy<ywHzCG%h$o^>'
    b'4(Aixue;|yW*vzw_;B8s*Zk$EzH%HYgLBtJ8)emP<{Qr}ZS=UUUuSQXJ(I2a(D<%f@M*Bf`&<zn39oQ9$u4aNW1+h@VdwPpfS{t<'
    b'?V8vUNNTr6@7nCK1VNXW%A;m+`PY9~V|K635{GrmJ*;(k{vLNue>-k|Sgr35X^ZlmX8;XH)zGb=lTY8$VWkR1_zne;&YpVzZE>-O'
    b'0pQ=U=ILM<6?ogoXRvanH`!p3PB>fqX<shzy!2u3FCRyx{#;mxlg$~O*Q15aDTDiP;fl$AxHFYYR-RvrL-zjA(Vb7_Es(&@^eJ2H'
    b'*1Wyulk;w7RKV$Oyg5{=IKvrgwto9D@&`D7Tu*MY<>#o++k>dt?B&Z_U~OXf)Ld9kAf`c<yOFxR!(KGiC5SOw?Tj~51?6r9eQ#k{'
    b'I(qk)HR0rGtu}C#TAvScI_gPBcSk#Hre9isbqRkxf$FGNwXftIY{nn<mG(wx|I{k&gM6@fB5*xB-LV@9w;=2F6^=({FzXU86aH=t'
    b'An&Ibf&tu7C>9+S@r^#Q&pTo_Wge6(Cye0Yrr)mn`(ICB89xch;Oq%%U2PknQCS*=t$~|Lv)zFeJ6&fAMXo=kD|P0cZGR$-<Oo=%'
    b'@(@3Z=g-!hs%Q5)>pvJ}D^)J#p@0rkqv>2$SRvK(+Q}uq^<T{AccDLgdsumXe~u?NvofcSD0qH}ZF^j8%MJ*1%&V&LcU=7_&DZ#L'
    b'C(;a}R`$6$^LHvnQ@z5>k^w)=J`;2}J8@(@IZgP(Z1WYH0N4Hg@Vt9VOCScDQ(-Z-yWyqOQ{@g_PEZ9LGNV7*(BCSxb!N?nVbhO+'
    b'FLwc3EuO%D3VfZ?A>r{Yp~qFY1xxfR656#-Owic&BKB}d2z+=GU(pZSJU(=1a+Z@)5N?Li4GoFUb)?S`c8|AYg39nfv$2&hZpiDT'
    b'UO(4gUCj^&_MLBT%7}C1)W-bck~F@KH@$ptG@N)yJp2i(sI92yC2OM|{_d?X%&JuB7)`m2&*8(`a1KxDfGg=0u~~vo=Fsv9RcE7@'
    b'E;w=>*YdN8jO+DlfW1$yHia%_hh;vbmhxM57}bbg<qQWaBlLQEz4APSyUFhO+g~^yu5IHvdpvk^BK4tUc^s-yNpC+aqE<4h_{#59'
    b'7e4INt6N6b5Zx#`HMlapF56QMI6iBgcCEXbBIXvZ)di-1Y4Prxjp|)-^g_Br?`j&qdS&;3H38KfF28&h{9(Kv5-DT(F=iq{XO#o}'
    b'`F8rm>#8_gU?KC@#p1Nx-`?o3Gb0B@c)_02Iu~*>I3!?eh{|9FXjO69OIMF!));q7Z#(}zSFJH?UXU;g!86p4w-Xv_)G)vL>ITtx'
    b'zFE}WhIe(wwj8uCZF`{Haubl$61dvy(^uZfMZbDtOC-yR^@j13GrG?I{m`s#UfSqYnCMU>*grhaeh+1}In^dqVjobBV_!49eY$yf'
    b'SZsC1J!~?=I>P&UseM;NfT@}v=xEOlmLKc^TE9N(FYttkX6ZODNzae&)yqDb+48rB8B87DP2!o;`Efmk03LD`yb+FP030{{B>O|s'
    b'u6Ie}mNBuG?HZ-3ziYuJvCPECqSv(%_GnCC%$}%qQ+w$5@vV5p@ArkTRJy^CD0}t_FFC?+p(}s?{1$wFJ%O)bW1#SPe-u7!o3e=H'
    b'(P-D<wdXtORju*0TNEy?cDon!6MWP^%dyql^B<!e8JXdnprPb!<x=|^owxgLD<agQjH_=|#_1GMTDwiN2`9fEvxaa#-yJPg>GPWS'
    b'JEbg#EYc;&S^NmN+-qv>Dly(9`cSjse!n)nP(JJPwX_z!aslG4Pg(EH&*^g6kaoxyKb-}h-tch%P0jQC6O@ZW9RKQiJN7X^I3tI;'
    b'*qAH|L0Waa=4`cI@qf#|8X1dIqgFQEu!Iz2VSiUWV^p~n^#`EuQI<!Zlm2umF`U;8P()g{mdin<d%NYr={at&*3>;Zr(ew5$NXH='
    b'mmN`)H}K5QL>0(uMNfZ%!FOa9*JmR$E^u|dX)*&p4Ak+GxZskG19OF_m8Wc)A6=?Dno-@VcB>A9tEV0eqop69_OP2=vDfkVtNFS@'
    b'-5xfWLd#)s90S`$DzbM9N9v1FXNJAL>N+&{*$SLPq(+~uk~|lO`hd{W=(AC0X|uOly5?+t+Q7S3us2(HGJUlh?NXVnEca|513dYs'
    b'EicP{{pp>O6EeSa&f}*&R-&~9AGMbw35!x0X<smu4p{CYbeCjrkB>Zd&{NyQWYDjmeff;--<`PnFl18N)7mv&m5rt)B$0T9O!|+?'
    b'Hi2KvBcn@IBm9awHM1627?aJAQL0M`?`9RJU-CB4+V~vfLyQb-Ab;(Pt-eeryIbGvB534TJ$TbSyZhN3BPw=vOiXVofS;w&W9h#$'
    b'2N;0U;x|vUTiajsq628HvUwrrIY%ux9iH~y=Y3fRwRZF9I@Zadk)}xWI+MwBY&hci(zL~w8taGkDX`W00$>}j-ig}}N=aczmULc@'
    b'&AJ1_rj*?CpRY)D>kWDVK+;0_)*mbW1wuaZA$NVvQ`0z_O@|+Q&xSlwIlKy44o1hus+_-G7a&%eccs;cnm9U`XVs9<F2?+u9Fx9W'
    b'Qi$hv$zsK6C(iZXoswZcsBR55NjAb;!Uo(RL}!njWIHngpTI4QGIqk&Hp<@gF{nP<;<sC(#_6LAEf#BZ<<91n%XHJ-mLKj=F+Tv<'
    b'pE`p{tX&QDp<bWW;M8Q0f4$#C9nHr96XGY&(7V?UH)!Zw2P4NNvCH6RO)=4VQQQ@j*vQped#Kr`QNyPvr8yum`gNSqZ@n5N)j^$U'
    b'Z<rc+O!DogYq^4Kh1)eLP`^12w|55#`wt9ihn%XLto#U#!|YidXxCxTsrQy|ZCdN`pDT!eul4nIL)-l?6I=S_5Uaz_+rY85A}B2v'
    b'KikQX`lzK=<f3;u<%(h2L^hl5^4Hr_t1L6JZMq~^a{l1ln0?UZ19~TotQj+B%^(sl*>;bj(<c1WzBR2^<e{RSBXk_PVfnp_I+HJ<'
    b'{vE=l!S;Qr*v@(%)TT<>&28;odwV<o{p)ksX7BmRIQU-ccu}WV+14WPS)E)PPsX$*i!OuEV-x+~vhf*ju8AU?t_aO~i>8dax~0_c'
    b'^xcO+QlzAy#I=MAsNP52%IWLRTg~?#g(`n>`l}P&8bh9oRZJLS`<fLY)%<<{1qmO3Em62Kc$K++(7gVNBgfFz51~Xph*Q%=NX(i`'
    b'o1+=Nzwolu*hEog-A_j`<l@~hld~_zU!lgf)fBy7o*($;PWaYbZN^e!&aLO9wsK6wjK9rN63;kbe!><<L)hFphhA`-w&C}kJRU65'
    b'xOdMv;~@)>I!zB4g&uZCDDxIrq%QqOkSBg~ed*}Vvj3aeZ=j8cZgU%ER3>a>v9M95YlDaHljKicKM;%o*`eWBtWLB;)}55Dc6_;<'
    b'hf__aX=T?$2Fc>tMd@vJiaU-trw{(~RTWZwydmA2=U=C#pO;Se3&HPsdVQCk7pK=0kkN1x46*KIOgo#hRLQiK*fQ&58gEM=Kom+e'
    b'IQrMtJQRg4?l?SX_BE*0?t=xftTsE)n|}{rGxcxKNGWQOR5Dw?+Nh3A*7I!Z2GXz*aH=ivFkWi)2#PO+KN3_UjF71o=(%^6Mb}e8'
    b'79IQVW7^4~V@))*>PIZKE~R|bpRLq+^Kb??mx}Cnawc7MNT)k055E7jFKaE`$WT$2aVv34(7p5Icpv^axH7v!(uF&YZ@ZO)g3!l)'
    b'EotTj%l4AMXOzx>dNoEKSFi3O%C5V+1bAhOjl3)<m3PQ^@4NWCv);qQ)~}voTf%u&YnK~m0yM8=gD5hsEzdWWA!5qazrJm<TL0sB'
    b'1cB~vZaukq<=`_OGL!c^HM8+oN)~tFT4rkclT>bH<}Vpqhkj(<Jv4zQSu8Am=kh)*RG_9Hy`;+wHlrL^=li-RIMr!sv}^&lk!%FS'
    b'Za>~0%!sQW<2X+pjUtIBk^A+I(0l;HC==b`V{&=%R7%+wPrKyi@&u>NeSKGj;O(y#;1ib)qOdisaRR_kzN8|m!PV#HlFVLgRvstS'
    b'4cVMNXulCz;IQR(zQ!zj>;7au2&wcwob)ce5x2wUX=~SmymGx|6a%_m5Bksaxqh#{AMMwdGG5k>r)1aemUk4|>q;-tVE~O!2d7}T'
    b'fkt%)4OR=bvoXJrUs^nmdd0=vI$96@^5yj<M{!bTJ6K!1?qA2zLMZ_!++Q&zba{5r6Jph5B>U-XN`fQva)qBaU;D_LQq~*j?32wc'
    b'FrnFE3luw`U#p8gF>cJD=<zI)-f>}m><6?S0QWy=h7R~+r#YQmk0(A751(m`t6y9Apk&?I4>c?vr}S6zHLoW#8keC_Y4O4I*8=6r'
    b')<)~J%5|W5Dov&VcHDXTxVY%?diqCA4Yv>WQdPfO-mHIUpCsn?))(%(iRG*E>Pl`lX8EF3Pa-tN=&-fAc1DeVp71lBIhC44a}^Nn'
    b'iKPfDf+^1BhSh&4o$1j(!d-hs-@@@ppHP+8RBXN5eRI~pu>73=y|m8mf+2?;a;>wtk4{$m3&+(U_8Y#0-Zi4L^FKemHQI)PMU~lA'
    b'yvuH9Dc5$bcevfOTshQ`7~DW$9~NaFlN+7Se!5c_y*H=;{4K=sX~?ab6RXs6nVxlgUk1h6*Oz{t2!z5k<_{ipn~?PfDSx%>C&+ts'
    b'whGOjJ}?YkfzLfF)VkGO#o>Ep=~(?+y?h_jjP8?9&n}Vi^A)tRtFD({Pcz@a7j`JIhnK?0{*5ZZ6T;cO{ffQ@_H}5?Fnd|~X_c_b'
    b'^$sWfsqCrVr80OPcu3#Jf16b;oq$%KDRuAXW<3u1)x*6%vY9#kOP&h4ix5gPkh0Z(df%nrx@^O5&2En?xa1=DHPr8m4&SPhYt#*Y'
    b'+`Q@IwPT}^e~x;JgOlLPl$u&!uT{o_SPkx%6@CdnlsTpj>79C&l4ubXkFnS0uZ2fdT2jqBWj*_EA(Qs(G?|Yt(;OT3o6g=9usstz'
    b'3hY?@H(%MR&NrK4CAfvPpf>BgOeEjdhgmP!50;MDXvK`R<+E2UH<$c`*fd_-Axv9IpDj7NY6%L(0W|_=^8GS7R@>LA&Bh-$Q;tN5'
    b'AEV4ebgMsJnNP;^R;3;<1_$22P|dgvKw~+(&+1gI!)nQdJk($Ia30s*JVi;#{B`E*YdyOh{#H*6gt+&YIG@{(b=o%EDzA9cbVFC2'
    b'mqIpyAtBM1JM{BesztSTANXK1XbW~5k3FMJ@uK7$Rc1-!FY1-#$jDDk8c4<6yHlgwV}S$^$p(kmB3pxZ0B?f1D%{f383F4PKug!X'
    b'nd3y=m{Y&TaD)5F&+C42zI~eK#uv}FFvcQFFI#ua<y=<@BaZI(09ETS9d_QBeog}?f{2+eBsqI8vwd+(R2NU%tt%IS#mg<|yrD9Y'
    b'&1E5_&JXO6ZRp2*5Dk8D7@5{=FVW4*J|*cSDG{%#K36_6242r%bw^J?apKw~r=cAW+!6*){aU_U>BnW9dOVlR7F4)=*ZSWkZW0m?'
    b'?;izDY27tvzuQ!8(PmE~{qtJv+?gUEYn^MC+8wiNk1l)e_8wHCHlIrsnJSv#n6W~d((GBWaZpFW>j&S7^kBSD9@W_~tFQ1nvoFUB'
    b'zd!MbQOz`Mo$gbih4j92d-wkQ)~k$GFL73Dw6yT}m`UYkm-`ZBHvbrZaH0SB+YGDssJ^vcG<ly<o1$A9=T&8}{$#hg_9e814+(Q&'
    b'I_vhDRt4TYx>Mh;x2SV1=)be;5>RyScjujG)fP%{AI@T;LdcDN)?Pr~Oi60AcHe?BZ!A^yC<lxLn-$MQiD8Fjmjv3^1eZLCrFu9-'
    b'>AlLM16J%Q6}=}vu!p$yzQk0U(1-2u275nF1WeNi+(+2Xsf$8fOq!;KoX8_2&l99*uZHQGtFD=eio8kiEIjWVS2~Xl<~F;PxKISv'
    b'DE{b79>53OGgKEj%#71Ix1OiUV7twrmBX_G@^?4ESnU-vE=0`o5lxoe>1uQ`;dSl|TOwT92}TotlcO+Rgzx0MU1Yb%UoL@@3A1va'
    b'cPW!{Kho&u15M5y*}@LnrZ@0mJyex<Dw;`DMT36F`d8x^&X3dn<jam4*vebql>GwL)xo8gfUbs{A$^R61Jfnrszte;^L(W97F5Ds'
    b'Si`^d9M7sBdfqH67cYE5wXKWV{k{(lZTUiPC$IX~5t{vU8;8#J^MQ=jt5csGx7upkk$^s5Z_d!INeLnX?J8F`E-|l<|0!EcRT{5i'
    b'1Hwe`Q8|0V)v~b*$crs&GDkz+>dLr%DLG7Tt97FpIYg3Gir<}glrtQIm*!u#=jRZBHzQXZp4XJy%btf*ec0m<U|QZKm@ZwaW-rCr'
    b'73QYww*>Ft7;1$5h70b*6-An2`L)wd;HsaOE2qJ?$ChvV6x-Ri@Q0&zzPQK(knXxq54iw7H+Ys9(dN@p#w@3pi;b6MC2cRoq(xNp'
    b'bOx=^+Z?<Ni0VjO?$@Ua(p#P?-DK%j9`(C97m@3rmFXLnrRxcbP~YPv`sb%NtCTM@kKaFp!!~q>5Ll~awL)C&{y1`f?hG1_4*fm&'
    b'OXhauvb}CqdWwj!Qksh8iq_8#bEF~Eadi{2+U*IFJG+Yy{%C_(YK-ww=|dC0*^2RPE!LWwYFJ5Ud}9LWniH|NdW|htyW6jwwVjb-'
    b'wv8mw(RFvB?jgdlPiDYfwK<?~M%?{?0N(tz+7;kZp1h|)i|}A&TTDAcKkfjrCH(9C_N0h$RJ}NOa7JxPkG@<R@P{hf{fo6aRLqI_'
    b'tt{7={LW@87UQk~ecI#)$CxVT)CF<_S@)h;Q8yhd8n~qs{Q$5DX>JW+v5V$qd;jo;Kb@^XcDv|i_N2iIaUS4+vwXfsQfwRDeKx(;'
    b'y-6#*VQFquABMFR7~H<eD`&Tynq2KeM)%egUSgwaNK#a9@&fmvKAwZvJ|}SkS9Br>6t($JXIo<}Rn^(64m(39bUQd)U3Ltq=NwwK'
    b'mAGa^kG<b<jd#$Ej`6o~I#y(3v+6+V&C!>y7CmZOY^)N^9>5C()aR>dy}UZS`PF+-k>lRz@zXa}F-oqF;@HHC*u9!bTp%?JV0rQx'
    b'@9CPdIl9*C6i~ax-uJ?A62Vve=+YVPC4JzzIvbO7c%LqIT&q=ZC&6tBb9Am%lbL@<7f^eIu_X8FXOosK>$Yc;?q1l1L#(nm=C#e~'
    b'G#<RdqP;EG=X(bu5k8Wg(#bsSUecirLg^Bi4JyaAyFBQV<k7p*;Yb*u&gEzoXF8XlJ#<VF!mup{`ILV#4}4f`GrKYDE_>1_#``&l'
    b'C*M+VOzK*v(kJla3iDp1HmiKI$D%iw0u)PPy8tPR(Owx_KJMMO=VEm3Q1D9*;CE+F+xr$3A{33@Ek^q|zrK_S?Y31M-FFN21j>Tl'
    b'DOm~kGT6ZZ9H7;@b8Wu01t>$CuamwHnZeX8y+}Ndj<|=wvybEP`GT}mTakabTOb>(xO2ds(OdVYDCq8vXZ8B?2k>@vyaINwfz9sd'
    b'`q;54>@Sv*%WesGT**6>VXd}#&IlQ9)Ng4%kpxU0?%q5aUj#pw)X!-P#Ygmkw|P1W{BPi#2KM>P_v|LJ6(#r1E`Kw{)f0i~+?8lI'
    b';!c@1f@jX9oHf@W9xN|8*T2QAUcJBdnZdOFS0!JoaV2%38ZU{<)_iazZc;oE;KU?=>63$C0QyU?f>-`h>vm&!HG$LUm**E?8N}hE'
    b'7wy-bcav(hcGj7TeWQYW^gWpYrR%=A0Y2?9DWEPPey?=rDkSUrRQ4KR`-;HTdueou41a;z_vP?=9b8{i)zcM^-hM{S^xCF=delZp'
    b'h^vy^(l&M(ka#j9S6p*Xt%nbKD>27sSOcjOe)qB01^3X&y}6<$^KQJ8`rhcs2TE3+0j<+;(X?~kn>yBr=#NWV=X8lNQWeIY*R1_?'
    b'8_z--2nAt_Mti*PT2r{q*8Pdsk}bh?DXR27OwFThSbUei(a-N@i-XP+o;5meB|NT7oat!kR<UoJL*>n_YegHVVciGS8!#nnt*WUQ'
    b'-G8&3tv=FzcN_LSS;~Hm>j}HZ3m-_$53dt{q+bz=x)&`=TYa1}{#N~b-&kk&IY(OGIbfv29$EI0L%sAhpKp3wcDsxNd^_CTnC-hk'
    b';(R4;)PB4&M!EqnK2GYht209`9AM*zhAi@_2~uQ|=g=)=gx*Q&u}|x4AEGbSL7Ft|H6xUXcX7pi!J74O$1!x=KD?SKkt9{g#OeUW'
    b'lx@@#yD{<mtziR=y{6yqxmyfP(&2}L&q}w`-v!mal`9mq>)pSuk=df$j%@AIEfEhBo~1T5ViZsOkm{<v@;0|geHERLlh08)VeT{_'
    b'$v^=sWq^d8_+Rgw%d|R&<|m}CZkRksl1MsTpRNq7gIEn$%hn(~(><YX%hO<sy914(3K;nNx|Z*B?2F0uw>3?-HS#YAh?RVO2-5wk'
    b'8q!oY5ah$$N|OG=Y|o~3*+0$6rFvZC#cpdF*-#V2VOmQ{u~Y>f6nuCL``rvy^|NQVX%&NJcS%HGw%L@<`zAb1fqK2&-!d1rz2frY'
    b'89v(<D82bd&Zrz<vcGwUt)Z+!#Jlf;4%{AW8U)M>A>uAWHmlvIb7I_9$!2tnI_FwKkOH?_zV6;8K+zPjhxy9_aD7}-#N!Ie?d_tR'
    b'0j(wVN6ozByG@e}_F5iaKhMvFdpro7qcjez{dyMe7M_IY7W0*t$U`imY|WM4`#`aJ^cvsiK{?ctNwF@#Q}^<qHV_A8rPT<ikld0Y'
    b'vSB_a@kV(bkZ@zI?xG`WHFECf?L2cIqZ{?vU%?Xce6IjK=#)nGa*6im!R3H7ly?(~Xo=kwz+w_blbVKnOZ_bTOE<j<bs3Qdq|O12'
    b'uzgr^z4ym2x|at068j5nENV_GeLBUDJ1i3Nz3@3u7p|GvggcmN1KczUWTl6JD!AK4{`$H;F}J(iS(wAYzHJrxQS>plP~lc1rl<Vo'
    b'bjA#KpLPG%w*mR%x7nx;FwoKYd+m5&(O>Q6sg!!BwR)@G&iHX|?ESRSSk*5=+BiULXx2vPZNLf8htZkZdP(+=X*FICOTlnBbMATb'
    b'7VZHrP!te5NUvnIubwCVO?ow3<f)qyGJlJbe|MU2qP^@idf$gQ?f)@SDr?*aufGGI*ILYKot4yOeDlsgwK-%VKv)_uEw=FK4zKP-'
    b'wKZBC1+#Kp%;dT;kbwef8S9Q*S*Dc^R(T$piuke~onJn53z8(SX$~?YiK|4HE;<w2AfY(QdbpB&o^F5DTKfdAY>BL0Q+<4a$#<By'
    b'iP}Zs|0sD&uZ!|*C@em1GoPsDt2K*!?fyr#EKHdYr()^;G@|Qwc1b$~ZG=O6Yt{P`<aFu+fYEA<j*5E5S7L9!mC0w{+*IFBe)<3>'
    b'l?sF7QRRH@Ygx$oi)ww34b~&iX^bx5AAAv{NBgbRjq7wiH)K)yoy(I7wgM~fWE+iqw$)iWM}D-&%IiB=XBx_r+BT)W{5l^<hZu*F'
    b'ge8}{H9cl?Gx7o(<wyJ<PlTQi_2u+$U+|hN*Ok+0)$iTbPOD=g(!@!B-Vsp0Cgko!HyH1%Z20iJ{Eq5_yT?CA&Nk_YsX96no39EZ'
    b'g9iD^tmeQqn)~7UTu$IrIO6>*)1d8EfN@-RK5R4!#xv{r-fnqQqI;3Z?64m<f9O3a!@fzSy-U($zq;9FyUO-!(WTbu*SAPF?IyUt'
    b'_jW4^cZVg7{mZ#Vn!9iQ5Ra6(;d@VdNA2Z%>5mAwo3hoo-LKHY+VLAWd830cNT0tNz4~4<toS@}Go%Ni+3uc%vayw($Va~9HT~6H'
    b'O`*!*i|iWq7<i+(6ot=b_H2CI`y#`l^?)g^F<&H`0rC<H!Ux7}_E8q(m(&mxhdw9&ywi_u*lsyX_HvDn<HmQjKP~JD-fwQJTeW}m'
    b'-*9!fJjjJ$EuT?!wfU0yXdpMR`xT$ON3qq}U;y0D?nX7zK|<>^R+he3&c(abws^V;^Vi<}cMrl{K0>EwvGy_oJ;+b8PIlL!<h4cS'
    b'vbG0-1yzqTx+E;y!UlE1TL4buy(b&PN34AU|4~^BrFR;F#;4ym+7v9|JzPRwRW7?s+IJd{xvBWW*eTOVSd*`1QK>UlEMxQzI*OPu'
    b'NHlC6oq5#e&i<~xoM~;X^U>JN>2)l+xwJpCQ}NN-u`f!$UlW}k$NSszFi^xm(!T^5o$IBMQdp$y{JTfB4|N3C7`K+B-`OC06|tqa'
    b'%H-E6mC>_7pBxRy$NPK)=F<vAPT2JI9>233t#sOUf3&+Rq2G6a72%Ng&LL_3?}_@TcBSmXM^0k3Q0-(5es|HTi!M(!%<Npl2Iq?8'
    b'*Tjh#i}|j7k(&11+<w-1%hDGwwRRZu;@LxP&x$^o4M&TBFo8w!W~=LGf51KwN@BomvV>w1YK{2wM<3zT{>_w~AC9tKKI~oJ+ZJml'
    b'@Oaq%Oecp^J2@T^lAj>)eB@m?u}ZBs{KsEzcU^use$c%fv+Y8_F#^s1$TnJM=<GBqH}__-otIxh!UD36H~KtmIg9XDcK|Sw$s0sB'
    b'Dl3O`hX%5S9mx6#SwM(9>|Ve7)4FkwA3RsFp~G?i!0I?~>a`G@3qJ*FZ}H*}69L-Se6sQxoJG5JleLgdFZ%%XE8Oh!*XQqC1|OsC'
    b'&8mCb^KdplRmbwVyVJOhv?!go-jo3@LA2eNO^)34Ht;SBlSBLPe2&iV)W^G!bP}kySPH52IqIde{PFB^HIk1182Y-ZPvCM)G5pVe'
    b'LvJslo>0yGAYj1R(q@)#NX1u;T4+U;EwL-TWAWSCJY4As|M6|}KCkR+W-S-J?c~f42PTgc(TBk>)3ST$3Y#{}YcmcAR&}-3Enbzd'
    b'#XnENN{JFzadE-|0=w&bojc#tID50N%RFumTK0BmEF=M)^KAWSC8Kk4LylUSM%(g|%z-EAP(xk6&CHPz#;0i|9S})I&Zc^+A9H{v'
    b'u#er($E<3OQx;zxifV^}?`Lz@wkhUI4Zzy4N+Xznz4GY^O5EAb*8#64CO7=m^Pu*r^tx?Dz0oYb^jVNT=0QrmQ@@XP!5uvROcu!*'
    b'LrD5+bJ|beFdoKB+pO!D)^m|LTxrS{1Ch5Lu+8w|g1~AUkg{;UxC_He8M?&A_&i(>&~AyOv@TQU66s*u`EgTN+POgq!F9qOCdFmf'
    b'8%-|+V=3Qi>-P@3*v*sW4wd<t@Wlu6HCj)na<kc^ph36#(4Qrsy&65sm0B>i$Jr6}*XW2)m8TpZETAzpG^t#6_o0>kWlTE?l>Q*m'
    b'prJNKMkYz`^8@p5R=P_qI{Hc*nprKqZq9za`Z`?(^bS7-_6!P;Z3$GG5?kQ+DvMqC3Dn5|1Q0~zQSp@zsHll_D>VB;%sP2?lh1Zh'
    b'DU{1Au=(LxvR8$>9{hBGv8b3HTVbDa1!Fn9@kf?(YkOWl&J`_n3I3rofFIjEo%0r-i`KDcY59)o&{FAgbNs%z?`oedqhpt}HI>e5'
    b'tnHtD_BHud<@Q|CFX#!m{k%Sk&?Y*$yVZ@-mhkTO1BZ&4lbvT*hr$P!DQ!8+O1i3Krqb*XHHD$NXAzRd=Z+KKqQD(TTMAI=?EtA_'
    b'ul;oXkQ&GBFrA(1+IVX$it@et>oKF=%loZ0tUb;CVzNLiO6{sy;ofT-QHtQc6P~(_w1pko&{Rq>c?Ri$f|}ZqtsJ{m>f*hT(t}X;'
    b'MUe;d*R=cIyHK(BjQ3qGw@2KOoYM1Oo#>i0ra&&q;&)OBDsA{M8cO^4X2;vo^SwwwCmhP#x3Hi=aq>DvGy=Y7uvY0(Ol34!9N-nO'
    b'!F@y9ZoYT6v_!hS=(_$6cLoI$i+S)sX!4&{$*sB4u^o7M7y8=o>N=!Dvl5(k;Pd}6o&8-EOAjqxeRumf4(k^VPY!)j89nZu$za^C'
    b'<{6Gv+TI<&WA$-WZK>g<^s)%2S$LZRB0OAhuOGGvsLvY*P1fCAkhc9?ed~sk;_hfFl^WIHhRwPl@JA@qEK^G3<1H(JyK?3Fs`bG0'
    b'!I(S(4PC59S#RxMg?&F%Pyl*O{$uYuw-iT~b^p&(z`>M&p*P-atU!40&71**BtRe}A%ll!znOASrmL%`XV1Rtu6s-mg_Mzzkzu}w'
    b'G$dITy8+KTimqEYkt-YfDodeOHQP@3ts%N(J5QWqrVzWvIv9OC77D}iw3-_5#rTq|H|^Ca<D0hWRd$gS@pihmZq|mBwH)YHJtH|<'
    b'9~X&SJk%3ffvQ-|t=ClN+#F>VE5pyvBW`RdZ!W^poZYne3za&jSZY~4G`Q*MG`KE1>2bgs>LAq{Yp-|<7T3wXB9M-c3Z~83z7+Be'
    b'kVqWJe(4K!eZ5)4mJSCl7H1ZVmc4slB!gv*SZTf6ZL`fb6?Mq2K_$Wl*v2|lbGmm~30X!Xo;1jJ?`Lmu*NEYR(>~&@EnMvwS+vT+'
    b'k>u)PVZoi<!a|5I<_)uW9+#xWaWv^?{F#1bh_tf)PQ*CNSvpg~aWYTU1TP+z?UC3%PXrgs>8-wtU~#*LLv4(0H?PX&F5hW|(>;zI'
    b'4}#@$X@9{m@?IP_lbbMCT)Ae2<A&R<&NDO@qiAYDJ00aC#jWaQqYltadF>&YNQ>3J$JTZe7h-*OR?(Ah?JTqTu`Sgqk=AZ>w2zvL'
    b'^=Q9i*~Jq!{vO?I>#~rD^Ox1in;BLMyr0^(m*-72gp4niHgP`{uY*=$97QDK9!`{r=eK5e78A_pTL`Z=ytZ9{3B|7C65k|ZrJ}g%'
    b'c6t?IL=JJwGL;rw%%Lrh2Ejt_UQg}1lg4rqZVE`^!ld`PNf)E2Wn_hU=SZR~m?uHL+Aw_7u1XaSqhLNcHAj<_+rOW9-S#XtIMT^#'
    b'avto5%fn5_ZI9)pa^^Ocm$75vY)48V$K>vikkH1}TueMR0wbH@NThcx&&sYSB_oAFFF)b}*+zO1G-}JSS@viS;Qb4Z(2)k_TJOWh'
    b'(>arK?8R8FKJq1l>Dn0EbVFnzk=oc<oWk6Z+*T}4jw>g68=Yfi+PvfP)?h1F!bj=t-hyq8DQvy(M>?KHGJhnDy>kV3hnLm|XJ{AR'
    b'tOw14mD(ImS5dA|S8tbU;OkgEVne!H3vcPy`HKCPStH&-Ho7TIDOao4vIloA{zj!Gd25f%`9ZAdPrBL2GT+_|%D1b%UiTV0??_6H'
    b'!Jxp%h~?OsbxZWY&SRO&&R0Us2U_+pzFKlr$7jtOmPz#H)B;Z~y!%mCM9xV0xV;CXrRmm}k9Z@;)O?M##z99t7$3MCEn6a#%Uw3o'
    b'+}Ni#$LZm@7kBOKS@#7K*7tfbU^eH|!K&xpE7h~K^T?5rRo2V!#WPok&I?gwldzOK*lkI5uN)O(-TQVqax35F*S#c`ZBb8`o3~Td'
    b'4AS(k&!wectZ~GqVrbj5%>xeiB$Wsr>I+AsyDN3VOfQ-c%0bDDQ{KXXOrn8enhs`f(_qhh4<a|L8nkvC1;>a8+mflHIar#NirrHT'
    b'LsyLkIuG_nr*oX49Lae0afjq7&{>?elL|ANc{i)(>Yh%Yc4B?lH~0JIB4R%=b&JrgMq^G_BVH(t&Z{QBbK5p~tg*{Xj>QDF$R$fs'
    b'%NL5~P|{tpc<v2vH^+nrv6{uaZ3vHjUu|;Vl*+4`d6;hUhjSu+y4bxnfuA{g{V^uo#<ATtd{5ZW{Vcf4a!Wt939ek;!eGLjeIRKJ'
    b'H8Q<X;JnyJ0;EJpC5k&P;*|uSjBRb1)@X+|jXf|?|8lst50(XjY5MN*^hxfArc`p2pWN)1;Ci-cpFETBc+j@nvl%ZtL+aI_rC~YT'
    b'%6P6K9)fFkA+<gakXm}4O_;;oU@zDRS@*-X<&r%H{WDB78|#(hmYh5c4z*x%)1{ahI=K_2*7a(uck{hdtJjGQ9NC_bvUHNMm@7RE'
    b'Ni01(#={YYl+k_Fbw^MiBTbyHh&el|UZNEs-*L1)moAspRh)PObHDp>4zYZ6?7UuFHV^F}4O!Rn{<>wk@>kN1OVquR*K%;*7)L9C'
    b'&Ys{Vv*yTQ!L##)$eLY8d)hZ%Tf+^PING&59#@+f6db9u7};M-%aLG_N{-rnl{N68yX?K>mZRF7=%X78H!5}3LM|L{`rU!vXt_(z'
    b'onZ^NE@xuRq@_8c^CTX>-2+_sP`q;6VwM=VnvGaPj60ajoH38ROn)}dIXuVxHQZa~vm4PDHrBF3U2HTs^=)x>ALboNgvt+soLKP$'
    b'syzUqGNXDs-NI@Sr)3?oEF6m#mE5(+Wsjp~1M7mI`gzPB2}zq>%6qSd%j1o_3|=GNX2D{2y5-e9Gp4h~p1=%IqP%TuEM`9Bf{Qqc'
    b'^Nb_5E~WPY=IWkJM>AADY`bemXN#?vbHru0)yvbJrQ;B}ewn--Cbd9h?8;U~(c+Y8x9=M)pX}`7)O8f6<aV|{-#qpN76yHO8E>?r'
    b'@HaKfc!Z&8rXZlRmQdRz4z2>e+*lGx(R_&Ww!|3TqnJDo(0ZuHQ+Y8@nlqbnw(72%69HU`?p-steZ8RavNMowTGB&NVx+0DS0CAp'
    b'65A4>+Ddjv%XOAN6f3=Q8{qKq#1-(L3sPUc4X)(?wv5g_bT4rNDRVtWWsa=9xyZC-s?DJ7i52CM=4v0z&Euo}CBMze?1r|GjVO)U'
    b'jkO!OK$O|(#g}aJov!5;YPvc_x+N8S!Hx|btx7?6!cDl*VR~3e3ey653=u8&D7&vl{GDBDC@gmU3Ndy?ZcDPxSwls8shL{^j?Ib?'
    b'E^fQ=VObE2z50o1FP(EC_$b(zOa{qF?y{YBTNkX;EKdTi^2+U>H_1WLkIPGf8mG9JchIM2^NNVGLn>TrSlu4!<mh3YwA(SUYzDj5'
    b'q*0s4og=5W(myV;P1bDSLr(StNjn{|5amVkgmGx15|7qnJKNTG_2r{mKV5V&Q@j(A69{qUBKMHhhNn);*u+7Yoh?^6VXMqmr(?an'
    b'TnELfWmC%Ekg=t-v@a5NS1lHaW*&PFwv7KCSOqw7)*6*(u7Y_}Mr%mi%G=EV8;RxaEhHWAU}ofS-A6|pFX6Ja+%Pxx{#m7#s?U6}'
    b'a>x}}-R-AZH9oHNN@O6**%tl6Ads`BmYDf*jw3Wkp_q`dxLbI$F!u+CkyIZy*ZiwPbR_j-Txv1K@)=JmwDzQ&k)}AM<|lG{v9@RN'
    b'xn<ZD-SUXs+sra!jmIP^K5$lcK}_h?iS%qJ<c~tJ!W(|$D4&pFpoDj`{`F+ONpZ81wY*1b#MaT8g|X|A@C`Z{kIU_{?76WIr{sC1'
    b'?rt{eQ^CLWhHJ|`+Y#AzI4I+Cew*95-0n0X1saE%y`GPk&I}PV&fZ=M$JKR)Qscch&f{BK?mWhNhxyh!%eQQ;UVpcDm%=nT&J<_u'
    b'K@sf_=Gdg_LM$FThAe%#tz?VD+DsuraK(IH5KnaG>R*DeemS|j&G_&v1SZD$uZCF)9=5*ojTp(kshK?2@Ut^+A%kHef!JobSjF$^'
    b'rH}VWI<l956KK!pXGdW*u|-y>-I8oB*NvJpmS06}qYGXQI0y2cy`9OGLmZBrxwX@0d;ESSfVg$L)#;s#_DqS$kk)d3oIZ@)eQ6fl'
    b'A7y;lb;qJep)^1Wu5N1(vkK;{edBVtvi5Yn<X8_+Vr`u6h5BLPd`=7DZ73JL#_E-uo3~bW?HK1h7;6E81SSqLl>!?OQvzM87wvq^'
    b'n<bYew|qMVdXpNJ<5PVv8|`r$^C)ExlPG@e-L}zT*5NHX7B0?4w|l4F?T&9J`{@GpQq@2;m1_BIZ0nw?Cl^O!Jte~1Cu`S)*eAUV'
    b'lP~yP*22om1J5;><{HvQ%($CjZvhvH?V()`Px`KYvsBF;+Z)zAlhNRuUn8wf!Obq{ey1m&V?=R~Yz|jG={~LTi#nQg6bu}NE!$T<'
    b'Tx~kstIYD?w!0jaYG#>SpiLsu=9zLf#-0ZDcA{%-h3@^zCUx*yZg`?Gh^<L>-^(q}qkyfJ>h%YX5;L!clC}^$T2j~*t8|J&FYMHB'
    b'_$WuQWid~RLyJ_b$bk^ZUp+#vC@l|Bwu1~O{dRI)_F1N<$=>Zq_0e{mnNLEDWj6A-@3x$yJ>abfmS0jSXT^SZuAJT2uw@-|klNf4'
    b'0a^O#M6C^5=3OOoPMo`k`Qa5|_U3pleH=6>8EvI&IjLw5iZQz*(Me1&8@6$tFCOd~#q4$>PWdBFD$zKuN<=5cn%jrPiL7ik$tlBl'
    b'8*3avTO4l-uoP)CFk6^Uf*kT-U9S$~BHjsf%Bdw&yrxP~n|$q?#lvQo4?D91I_75?DIyJs_<bT4$*73UEayeSoZA&*wtj+599zXK'
    b'MtgT>a?Lh-O{YCztM_|1o732*SMd;hn+_5VcEzx+ZO|uI3e)|lM@ihY*`ArZmXx)APaoxCtG*Aca;JT7!iNDGiG^mv3R=&k3RS1K'
    b'>Z_o;TyC7QON^!45w2p_Rlc0a<Zx(>8fVSy;?d_l6GYawY6cpMXv6Jkj;A)?X1|Ms?19>`dOYPitHzAU(dlMkn!Vz6Vl9#8BZGCB'
    b'(0x3zoie^*C=swTiEbQZLjED)*aU(TGu@e07j*Mt=sb%1$xgL#@f4ABJLeaDu5!e=OK`<8N-YpuBvYy+97)3CNqH`phG)-)>-H?)'
    b'3v^trK{=A0Mv^6=elPi>qjEqjNZ25`=2n{xA|0?$r(L&J1>QI-jb6L$OEY)KbsLB9kPDwKtjBT{oVW62m&{_xb+fuSvT?T<#{f!k'
    b'pC_GQIN7Rm!J;(VdYbu+xg411{NoK@^LP#=%(EUI1E-zCcM_!9x-@bfoyPeTwzXmy8)dF=%gizl@(ZVU8Ty)8$Mnv*-TA@M>?o{}'
    b'-5FbsBz&H(a(!eNpB`C~x2L8Zr>|G?;!T=6GSz0JSH4OS&&=CGq~PE}koP+~*_qctqYmJ9Zd2Ph+q1Ym6EU{TB@zE2$uI1|t$*mm'
    b'd)eqNOC0mg!(7<SJ>Gqf4(zP}JJY^P;24h_dvrbNub}q<Vw2eEfkS{%4pW&>V9#y)ba7rG9Y%el;o|AsGLGH)4gYT9wpdonVrEAp'
    b'`+1A+RdCy2YiCR7HhGd4B)5(2n!Yiy-`&p`f1U-1xwqFlx0^}cE_KGKvQ^ysEX(L>-;b5Yi+c5(b(U*c!_N<Qjr1-<(7{}7+qz!T'
    b'IrGUS-8*PSh#n3NYSi>?c2O=ym%G;%UMbqfJayh>*1NdNZ<nXn{^lHL%0Ti1mhh(<;&oUP^Vu46%OCyHR6r{e*TBeAd{@+o5YwY&'
    b'-$~gT<5D0U!7mmG0KRT;Ddw87({9aP*VTLj+wn_t%<s2(ijhRGX%5CG4cocPNhR;O&mQtQ(q<l<`F?5N=u9@`YL51=+Z}i78M*nS'
    b'n{GFE^+dVDUHuJbeC?kRu1>rXT=SQkocBZ`gNkK^J3{SVfT%gdeA=CkSB9>2oIDJX$~v(@j^@iITx5}ebJDk3%q7Z6pGL=GI%jv_'
    b'vcu09dmWcPaU2W!2SH(%vXt+BInH-ICw_^}noAqHa1z&yoWLej(M_TQM<OCF59#D>O`qBY9{2WyPAM0VQ)Fefzg2?fIgTIVj#}&@'
    b'P)?j#Z_{?4gEGb?jBU%3&9=QP*5Z|AP66b6Sa?t4bgj@Y9WN}hMpB_F7AVs9+Ik=mc8P5-!}dXFhx0L!Pgw(89YNz4f{7Pmq-{4J'
    b'R~jfjANqKandAmks+WG$=Np16M(=&ad;^(e?X_C0W$y4v0E6q3IkBWGvA%6*9iEAa<J_c6{z9)%T8^W=ZFB>2FuYahZG&iiwMMeu'
    b'?O=4I{Rc7`AqMqh-9O1XOIUL@H0o^JZNG2=%o?h5wn*OL*xpC$i(I#-v5^Ga$n?U7Czq9N#MV>x8@tERTG^U(<bnxjA8TCVaW^?`'
    b'X9L0c)N^%V{Wg}80&Ux%*TSe$EtU~|iA~Me=MXz&O1L-R@S>x%C4cLSiD?o)HSR&%wwp^XvAiEW^PbJsn@hW^lQ|X>bJh}#5<CAb'
    b'FK4Z|wODZlC-ZiQZKQmTdcm7qi}azss8zci>n7-0*WE^)t<Emiw~deJR*TcbW!zt1N@9~*a<|;oJ93T#iMk(I)N*vQTa?I1JSHUg'
    b'aojP*Ci@ZLzE<qKeVH6>TWx#t6mGQbp=Pp%t|)GN%WhHrz7JmZq;c<D-MQpKqk5?saM<sb`Kewy+M>3-#n;NNZMJx{cWoY!X0@KH'
    b'30?}bb`PP{c{ZCbqrqK{Z^rxE811p3nNH+5wOV=adDw`@E8e{zgVdblY>DKCX&7fKChfwx>K#@R-eM#jDksJEXwpr%<Tz3mvsQPR'
    b'TQ0dfa*bsz=O$|FHb!ROC7Ez7j?r_sxE+npX@3L6H@;-`pymnHNEKM2d@i{h@s+bg@?L-4$jxbMk3XBkX8LrVEMj~xH|~{jF<q^1'
    b'(D@1r;fKS`!q+5Ej|iUD<H>#=%MS}XV7Qf9K#p46xz=vE%JDZ3b+b#JZn_&@=JUhbN%oZ17;Zmx=cI9_m~j`wmco95(`2i2=truf'
    b'fw^?)Z+(|^V<OLeKJnh%(M!~|!9t7bX^;!03cP*ScjPnUe8j#)umgIVW8N@kDP_?J*BZvX{+u;XiBQ-5Y*(wF+lCC!nMzfvu)%Yv'
    b'klyx@0#e*N7h=g*V^U|<zS=iEGp2OM*u1$J>3g}Za7o){=R{&%%rI7;MNUrQw**f)BNJ<!Kki}<IWyjO<!v;FU7M(9bO@h}HI7N}'
    b'*rz+43AV%&WU4Y3HhHSpCF$`bm2KVKwrFX-lq>Pp0;{Ej!|FH<H5^h=7822Fn&=caQYlFVI;(uEXI);pnKsdF^!L{O09Yhn-G=(s'
    b'h}}5jQ@#fWRbsNrwzBg>F&S!JoNmEf9(fzf&b`)%gksFLz3fYs{VCpY)O%$gR@$U5hqwj1lu6q*M2#x;@L=VP(^A&EC<e&QH0szi'
    b'(n&|sR!dwXsl0)Ev*UgxA=*1TPit}F*F<Y(kwJWmc*j$Emv-Db&enveX0rL@7Kyv_Ve5!k1#O~bgQDhqEe!AXEY(WR8IyDh4Z@Y('
    b'1hC6VjLe&({d9b$U3IEpj4N>FZ^dXwUiK1qw<CRMJ1u2rD3h8?=iQ-pbljrb%Q${a4fB0RHcHj<k-AM<rXy7B;7<kew^eJks?6Gv'
    b'IOniku;46oxkc-VbS2vz6yXhElKi+ctrkYTbMG`9PtVi4!(k_H3!)X6*(QY3NTV}uP|PrW^o5JJaAfUmFJ|>iGI-5*XSUGl*zXM7'
    b'R$izy!X?3bJnwM2M2uU>jki^F3d6j=iX=MMmVs@q)oE`kc+#hM11MEun6Pn|awWB}u(<-^TP!N~W6R~ck+TVBPTQDVJXzvnE0CYL'
    b'?t{gONU&!<#AkMs!y&)#+qYqfY|><879_|n-#G9aM{jBDovW~P6brX;2eN4<+mrc9*g8FhW5I8}O3C=3-@^~?QoOaBW-%MLTN4B6'
    b'Adj||In#;TC`-oU4Iwx#3PiXNL}JV|WLXRNv>xTxxWgKB)$Hwj&^QAgn}@48q7W=14oe_RJ0>j)IrOrbe8qf><EZDzUDNltIb5FC'
    b'kHz3&yh_B~X_C0adR@QcLeF8%0j19Xe}wwB8zl-W7nO)QuiNr4VMR}T(YrD3GELlyu7-azS$iASi!VhboWVr3X<K>v^Jx2?sd}zW'
    b'IyI}TLR%($3!Mv@7;k3cqZ#dP$d@}YDouGjbI-KIdoU|!>!+rzMuu4KZgG#gw~=`975zs3HQn|1Sh|w$^UH7p?|0{w^T@LCX2LVE'
    b'l-cZ-q_3Zga?}A$V$qJZ(cuu~#)?7N5iX`Tkv@^1Uwu=`vrJJS7s4%V+r`=~-<&=Gt8#Zya2K<NZp3=_4IZ%6hl5KVzf|bkI5iOo'
    b'D}%SuaxG-NPp+Y3{CF6(W_Z3`TqK&&ZbPoM%H3_wGoWnDYE<>_Z+n7ccH^cilb@v4Nq!c{hWTLh;<NL?v(M<u<wu9rwf_=o5LU-('
    b'yEJp{l+^8y7nOrpUdCLN#WFTe2s895RxK`hDN}__k&Szbc(a#Xb7gbCvS7!^rA<t7Rk_?q7R*!HCUuYYst;Y+_zq$-)<!E)4BM__'
    b'oF^L}7APc{yt<Ldwc#AN28%sN;cO$zaj?1Fb8Y|J+Rm@WX*6E-ZOxZix?QDjY;2Y;hs<FV7`AONL6?DvBR033vPdC&r1}}!$vkqs'
    b'O0J8A#f3#W9m9!v$Xdyt_WN<DQEwIdqePoF-vW-Kd70T_vpr?oO~jykwDQdAoJ-F8J*DKGXOCGs#>5jH4>^<w;&vL;vd#{9$y__V'
    b'-LdL-8h64k62)9DldgLk;xLipV`SxOYm|?&wb2#FZIM{n@{VbX4fbNh(QZrFmh|9QIbn2p8@GpVG)uOM(d&@3j5*udf#w3zDUA$k'
    b'Lt&I(4bF{u^ejJq2chc<xCdwp+3}A4c4QUn8Kzn2HalI>+=|ih!g`$(rl(qH#BLn@=%hL9mXql&8}cmn_4XY{$L^W0z(ncZae7%r'
    b'veiJgYO_?O6XP1CM(&6!9l09oUxA>dQn^M}C9#t5Pn_rYdY<Y}N1hW}*^c?llC=iM!n{Agvi^)c<xdTR#U0*S3HwuSG)t|{$zr5c'
    b'J&k7B(RPBCa=XS_OpBh|&R4=YpFgriIwfPz(xtRU(Za&Qds~;7gr8R2z#+v(-srL)l)Hx=ccuKb+ngUUtgRjGCF(IRFQ9=v?)1zF'
    b'Yth<>c6ziVh5J^{=C#P_K|IIDXWaELCFd!pZ<WfX41CC2dpV!PEiN&!S!(-(fkjs=yJi197mf7Rb14(G)hoo<x*y!<Hj+z5?>7J4'
    b'mg~x5tzQ>cC$f~eI#M*v)LT@)lIqr50<}1jUG(5OB;D0nK0_M*@Hlo}n%!G5!N+cBHMI&Q&WMG~)P;&AV_U|SRw-v4FSxwma1;3s'
    b'!&l|}pv{*<vo_jFmRoi#3XqVPuZ%$E+nsxy&4Z^9UB^mimRJXSr|$T2H)<&y8OnhaVQ{ycj}mL)r<L_8O08OjwDovB#WvPRkVgCU'
    b'Wpr7s%e`5ywcy2W2gBFV$)>m*Wa>H0&m|m}^kOXAFl=a_ZIQlb6DRpveuCTr{X@uzl^4m}L@(|jg>&4LU_fq#xw@mKhmgD1sxPoB'
    b'w~~#b^PVpY)*hX_BMWA_lV<*2qtp~qN1A2radv=g3!b9YI=@wH8!0w1yQX#PQFJp@?Z~%DWB*|ryN*{!Qfw2Rv5=E;sRW<%H_YVN'
    b'>+LtwQ||@!#*@)zD7$O)mpGR!6Sn;=n;{14bga{L%DZ#QJjsUykDHp3iCCssvAS5SILahAv{Sjw2OFPJKip)o@eb`zQQt^N4EaPq'
    b'G2SrSUBJ>Fbe2b|*z*Tg&C0=Z8j07bB{@DISgDJKLzdPtHI5hBEw3+<J=QANYQcMAL26(0ox0t7HJNjp(Y_d1&K|!38mq@$W%iPf'
    b'M5EENknu20Z|)$cLgv$M@4KyIPOQm#lCegHIt82kRWy-2Rot~3o~=^rq13TwF_GuHyE4)=H@eg5lABs8Gqd2&pZXbLeD(`B+Bhq1'
    b'McGbUt}$412eSBkl_<>2aWoU8iSZ`g3ObfPEIPhATWx2xx52J4WZKWSmQ9Z>F{#b^fx`5FAxG=6U3RA_t1FCo&<-66gm;^bFR)sM'
    b'#)aVH_Z<*ARI)b8V>GkQxWrQ|PLugu)7r_O3)Y1TDJ3j;GuNj#$pG2)P)9QwikG-8<}KSjy^&ZOb;(PJHKRq`-$Q5$t@a(uqJMRB'
    b'Br2;zXf0yVLetQVsf;`Q;h1|J;a9Z*dRcTY4!O<P%Ipl21Yk2UkH<$RN*Oj&qN(AmzGBL~qp%HCbA8M~5vV*Edk*FBXp+uPk6w8*'
    b'Iu`=N<jIjl>dn&4XFsKkbJ^DYZWyz>+^wija&E#S@<Iq$tl=NEI#}T}+f+wnXm~snHq_`6a$3>oFq){i3k5UQv52Wc)?cb-Pa}tY'
    b'7o08dtY@|_abVWd)@d}%m7_l19lsd4d7#ml7orEB%UO}m8AmyY`p3wy5##3!(Vn^HcCry^>^GLcInP|^TEx~IjcB|S=62?NXL^rv'
    b'jC)IkTdP9L(W{z^3)Yj$wWW04!5vdMG6$mJ##kGjt;+y|R*UUB6>iY2R{3_w;ZcU0ZgP%e0^1g^B?)n^9l6CYw{MO1zS%i8CkTAX'
    b'W0!#yn}i$r&ZSx(9$U8dyliJ|gX?Tgw#(Pm+Tpsi{IYLioY!lnOXpj}(@z)d%|$LJ?{djatymq^f_7F&4*?2YUig5e+0P}L>1Y9q'
    b'#l`)`9ph!Ut(oWUo@)0TbJ%^eyt#L%B1eb)$S&-$xFerxOFi0gv@X5IzLfQ5Y3~vV|EeJ;r4ycsILQ5McFRWjUA{+no%K-s)Xk(y'
    b'?({ytsu3W?=r2;9qkQg2g+z;_8u8e2(#?SMODuaszM1QAFuOau&SIU5_gnmsU-k{1H{V@lF5We#gGFy=oA+K4J0HdckCQ6Zk#TQs'
    b'P)(A^a_0>fo$j%DKvyQs>Vk+fwcXrY@w$=qc`_y2&7tK?G5+fg4L7R2V>L1KH^U&+4Y@|Aosq-h6vCCPb0IM}q*`T`$wiO;Wv8*b'
    b'$>Je#V+wU-vbI>9NM_mQ5S&M?b+Jw+54EbxGmg$^`x1?XeAEPOT&>|Q03@r)dQt>_&f~GAht8;Pj%SR$`kN({I0p~SRG7`K#p+_#'
    b'8uph>=PtfU1U%TX8@!L;bp%)2IPaW@SQ(v&Vky+;qxq~q6zy93mvENNIAk=qPL9k{tO?>mzQwrny?l694pqD6t5Jg$*z(#X-zY2)'
    b'T0}D~?3mwGCbkS>EjrBBq8|}><m5d!X0u&+l)nbDh_nc#7p&j1E+mlbT&{#>LQhK6Ph)@EkqWO)=3YA&xGwf5yK}L0C#~hIaW25R'
    b'PI8UK(T7jnY1t<RDy{78Fbid_le;-|4bSWT$-)})B<q8u-C7j0*Icxp_jA6*s&}pikTs7nZlO@WPg4F3o3Yho7KvntOlOlZuWvwk'
    b'd!3n4?{(C#uGyAJ+bg8ZbxCs&V|uCdz+#@I8{U4@%dlv!6>UTkjmkL3^}NY@^yWWjdU8jkG8{=(%!vzm_j>1qr+Qgc_Z8tbNmM$;'
    b'mX-3j(pxuq?HT))1FPLuZ2R`3<}Q|v4cg5N;yIEPZ=4SI`+?;m*X7-=6G&RNYd0#lCfQrsyuiuRjP*6Ebhl$omot@vaBEqe%+fI@'
    b'<K~wCw%PW3w>B~`Gvnq|FxCRh!?e%i+SHI_rCFvLJShl7h%5#8l$;@xNoy*;$uB*gTDLs|5bHR-ri#_@J~S#M&BgdFg%rYv+9Kb@'
    b'=)QQExdOE~o1yR+KZvo%ZsYE+Sx-m9zR*Ug-rr67=~azNjKnxbGVXe?8;Kw-^E}}fBr3Sh9G3-4i{IKT4pxi`of=R@t32*s=!E0i'
    b';*hx~k@iPd!CE<VcAdJ>B40i^I_nwby?Gn0s&UsxbVvB*O^g!!K1ZRnWX^04#qEb<;AHWx4;fo_#CyhDp*;*FNL#kNjI^5Mtx$-|'
    b'R6lzl>?yB28eL+c@idx~Y3Vj85}7SMy{+vDrrrsq<ZWkvH13>XkLT8zWPLqbwO#;zhf4OyV!paWX5EBfo<yqMY7%SI5)4WPJ(KW$'
    b'O}Q<{;{qMj8NYpAI_3k1kPqp0?d20T7<otI(|ue{?<$r99%Bx^^`&myF~0HEMJ|-V)|Enlh_JKmIUj8_lBxT$pKWzfz8(!nSO%$K'
    b')M7nN3)W7zNjAgYDq_3jy!m{rJPKtO(`iyj9pbFD-rvto1?Mbhks2sjoFm;*&uQSOUTivZrG(W=C~d<>*0~ON*7*%5OwucPT#-Gg'
    b'<9K@8%*3{*c8m4W7-c?2{G;3+3D{P<d3-r*-xBUa?_{6bD|oD06|ynJm-S*@ev_c3M&h=18fT@?_U0j5DR}QER@!xsrIxKCn0<kJ'
    b'uUKxM*i$pGJ?v|(bGPb}xA^`dpegPiO5+Dw%GE84xNTlRw>>Wrvd=xMe(;DzH_U#=Z5zip#-wwUn;MD6y2D_U?_{xP*DiZzk^Q)1'
    b'CqWwQS?+e|QHn$k$86?S341C7%-Wdjax+IQBvPGGJT|L4tUYej8lO0OI5qX!tK@l5v!5E-wNr{G(i8dAu{ciss@yhy&zD*WcWz%S'
    b'_fsoDoChYCR;NKEf~ofGj>;A4ye;@E3Ax)G?s|&^RZOnSoq)R$EiP;PJYOEllXbkB_h(DK5@U9H^R9koEJta(`<yF#(&a#lG1JDL'
    b'_LMXk#zWz~nT#gWVK>X%JJWoXie!f_+3D;COLEE?n;o}xZnzsRd-20$m`NPt)ZOl`O%A|ChdA_bvh%K>xpF-LG{@1|jpuk32XVeV'
    b'ttD-NmVtZu)4D%)rzeZO+r3zHx9*O$?x%W;b4|oZCcJhnY%v66eQdSeYhUie2~I~A0e|pLIIn~Hb?DkT$ZRI%XwPE1Vy_k*(e6aS'
    b'Tt3}`s8Fi4_kmo}sBhF~nUiafy-b^j+#F#3Swfz=4<%pGZ)Yb_Cg7~Loa<6Eu{<_y{zRZz!pwC6jp9x$?H|PprF}VvHki8Lb~d`>'
    b'`TSPGYrQnvA;Pz~INI5^Xsu(^HwqvsMVmdlJGSmdL4<T%+ee@Kkcj1z=bbqRFF1>m&0fuI4Hbpb`fjz5J-?Sd6C*bn_u4}HT|eBk'
    b'Mx)NQ#UF|bNs>Aq`EraH2IDo^e@(Clzv1UaGn4dhE)H{v^`8pWZpxB$6na964Pt#}lWS-1=_x-f2Rx&Fdw2}FV>j6u%Gi=U_D&re'
    b'*Hy(Hi93sj@vNAx9!l4HL$<hQ;ema#E#B5y=PH{n8~XvKova&phP&wYEcb)bdCqa$lr<o&T0(gfMD7uHikVY%k)_>XYxahgdb3Jk'
    b'U3ArB8<6%+!+vk1X%4pRZmV_N7_~C?g{QQdbus?RH*DK^C6vGn3}8lLPIkQ=cW&`D##pD;>iOcx=d64zTAAD~7s?xmY)db{Ieu%j'
    b'ONCM$t$KaoX$i~KyQOX^*D)nb$V-P}C_<t+7G=pSx833_DSneEQJUg}B;(9<&dDq}6**ZTs3~|l#TjNA3QkFiU~mD4O~serO`j0r'
    b'1bRucfRryf-BQwuBgH8$P*Yx@L`v9Gq(YWsnbXu8n&Ko$k)IRfDM2Ho^EIbgl4h4vfm(w$;&e-kBK%uC;5-jHAZ4DR30zV~a1c1~'
    b'Ou~gFC4JtLK=B~|1_X!|&Mv`!wQeDm2ThHMCy7iKIL&-c`qBKk9W72-4#<8gv-D1;wEjM)#BwZ9Gls(1>7EiqNCxsp9l;Dv367Nn'
    b'@Zob3`tY=otZ;Fq(9q?$lyQO7r2C`Up|-qqdK#W8XI1btLlTgZsI=w;@ryJG4(Q8*W+X84Kt$@$L_ie;rWGek(}fJQQUnkJyap6>'
    b'juV?7a0x_pnjQ&`)P)R3J*9#2a0gcFLGAH#LI+OREEw(pMzY0eR)h*nOY|P7g#_M$qlH5U3QF-5_=lCgXe~=1JP{ZP2L&`0i50a4'
    b'e?wZ}J5q+<DYK;-lgw&!2&uQJJxv`bNSUV@s!j1YE$EWm@(d*@)&~@i5=A%*kgCiI6a)Gs4V?iJ28>BG@y1?%(1kz&?g<LgV08W!'
    b'r6dT72l6FkK>$y|bn!eVNKeX2vrvJlAJT`P^_LBs=N60UN@h2jGK+AESw%s>D^R1s$aqea=q<j~x)5bX(!_oQ2B)wNofFWd1>o!i'
    b'{*?u7Jh(`S?^-E(3C78agh2BW9PJ+Ve543j8S|VvanOAp=!L{@)n2~SH*^^?5b;#p(7Zk+8y0FK&?HF)g2P$p9C%!O&&d`jvcLj`'
    b'7L;!_fj-%u?l7qj`qvxj=Kky;r*j-=FVtIlK?C!9#TQgc{2e{5p)4?lW8TV&qXOy;CQSh3v_9q_xG?W$<4g(Ml-tr0R7dIvB>d!1'
    b'prD|y0%C%`9ZV<%T>xYZNQj^q!~4FXxuQX2VWIX=60L+SrHLwhQ3f^$90Ey;_)?&Nsj<?>Wb`))5Ep^gX;G2{>Z-*@mYeGCSbaw!'
    b'0X_geGccIq0!`_}fNU5Fs4|#g1`dkmR~&25!DWftg1|sbIcWuCulDi@Jwb*8+{rZ5qZLqg7_x9e(*`hfz#Gt3LiO&@K%`Ho0d0m3'
    b'0<;DaqD9pZU_)KxEcBv^K2o2JQn8Y`44glt!m%)5Qw#W|%GbkOAaTtOfYNjP52+G3FTs~L6a{QXlz<TkQwDlpNQ$AiibIFc0*DSw'
    b'|EJPZV*&xEPUfcvTphInfGAa3Q+xqK(1vE1&*i50XUz^o-Ph|LPvc0$7r=Rd25_RL61SmP@e5Q*Fu5>xo`9dCaX2eL0<7X4I2Kq4'
    b'qY?(H@Ch+|JExa2CyP2+QFFu4)HJ>g_5YXz^uMga2MOW{q@Z)Sl_lJmPD%uG1YH0_vzt$Cf#7)Rp}ks+U*W(3iJC>wEa-{SqqFK2'
    b'Kh?a4(^!jupAB_-jX1v3O!tF8&=hp*&~V_iK?kPGRee-a9HVs76iDR@-zwr)n3sSvfdO>^#4S9e0syq?bH(oxQ#%F!*@Jl|6)>O}'
    b'Aa#V_1BC?Wgi?80%gXyIvrkUvBeJR|f$ZVHy8^8CVDq7<obZfmp5*lrMO|93k>b=}4_5-t5QJnJ$b;U>0AYal!2c};4j9=p@hlh~'
    b'c$ih;K^JhOfFn4XSN5sCX21xAbr}ApbB3F100|%!=w@`R_$BhM1*kwCMc_0mQA<igNx<y^@qtLlXj#l#`k`P}gHLbpTp+0FhZYlo'
    b'y)eN3o`B)h=XsC>4k8r%gf4{xFU~EdU^<~T>4_Btu`q(XN-9_d*J|3SfW{vYW~qaY7<7DP<U-&BgA;0qH0J#4WZ$Ga074KOKvjzf'
    b'`s^wwZK|n0c=Z#?km#E{P(w;{AP0d{P{Nb<R;N%I&L>or@Dd0-9MT+E&I3L_PunAYi9i|gt@xQbfFKwMK6K4sROXig4&%)H1fH_^'
    b'Rx>H^Ce%mp*H6ru608-zVdkOhh}P+6gVv<)4XP<FjW1aUnTcrtXx5%GaQb8L&tCXDR3V;zYqj$ebZF4^z>bz6)I#f3P3nm}umUCi'
    b'et~D*4Ly9mKyd;91X_VX&v6Crpa+33s={l(!{bUup&ErjRLK#Z$M%^#V2ML>-wy>ak`yQ<2B){LQ#9}`%x*rT3!EUt=;XtQj1)=J'
    b';g7PvFNhXKU=Y5aqcc=Eqd&v(s+kkWnbag$!Ps+ALz$oH?pyWH6+@w{xQIu7O(@y5YRk|gePIGW>H^AN%}W5jg|h-k14>H}q6D=|'
    b'rLaIV)R(4m%EA)FlU!BwqZC7wiTgmcDHixVLMwi(fbih2t*9NpL%Xl+Mu!AO{bL120HN4i*79!!f4oLiYUcTaew4=0906q(f`2Wg'
    b'eOE5fXIPzJ;=u}!D~xI!DP2N1NT?}%M)lCoc!`(i46SIsg7hHDQ;bXtxWHkOoI3TY3ILqK!vI2kO50F%U2;5rVmO$~LZbktD{-&<'
    b'*gPD3818qeZgG}gDCAYUJ;0<wu~@|sOkt|<F2a0&{EB1I8B=sl19=bkXxNsnnz}}Qm+ITX$iuPd6%sYgnhT1Xe45JVN&d78E$h{$'
    b'+L$p-<5X^61vu5A!MRjk`CKZ{S`C+@xbE*my|-%kDP=>sMR~4O4;3AUut8KbK%a}}UX2bFnKX56Z7PG$2sF8*p4FM6mn%sXhbEu7'
    b'@{UnI6ID5AMPpU9e?Zv~00(3sQ#xVrCuCZia1m&y1VpE5m1=)#K4@UGPr7)`>pRf*NQv~A3X~qCBDj(p(=0DbKNJs~SFM|`>FBHI'
    b's#QCG)QK{9rNQeFeKk$^v50hE`=sVZ9ET;;ImIZ`f{RbSN6>;`o<0K7un$5DDQyZT^$Z{Kqw5hjS0IX7V_8sOW+?>)0BzwFnSo>&'
    b'CTXwJtsnJaBx@>lh}@KX;jp45U~o#sNUwOndIHFO1TEq!ewt8fq(ABf%%WnvdZ7rg4a>_oiO(559aicKz%g(lMH<0Fpd>YBd`4Y~'
    b'*BU%l1!Jt~z)9Ao2|Rp2L0#=$r~jXILO@>#a5s#llv;BEq9+)c)Rw_yB^`Lqbk(U66g^k?`r(AD64mN04=A{#0IC5Y{;Z}0iW$K1'
    b'E+8$f7%M4as^f5KvOavF1@hDDtTW<&1j1KKW*@8?e2*5$E4%^dvp`m$>ApXpfAU7vD6RFUWEt;*^!F%3xJWTdYR0clqT;NK5<Q$M'
    b'*ac;*Wa$AN(0TR--{qT|?t_NH>ox0Vx22mWgP+ueC3T77b8#51N=YR2_@;*cXF%~5z3VOy1a<yXsi<gG2f}KYc)PHvmi}PXn9{HU'
    b'oCT%w1QRl&1ox?Y@IAd$HJ1>W1^7pEX>VPzzM!HS>>~p<7HhuO1F#qUZD^{T0G;_WMBd`OA;JX(9zI1a6%Ktq0L3pos&smmqsdND'
    b'6m@R3>cT5E)d0#5yU~*xrSzyFA0wKGdfxgRPoQbRB|Th6z~7x}wIrkAbajeVPxh41YQ9TJC!lIP$w(R8=gRsT@hE)jum>o-Zl%+O'
    b'z-_^Rlv0e!kFu-<OO0>5n2M{u7q$HUsQ-1$`ayGjluAP_9Kqta!I<LnG*78VrjNYqTf!PAYK$}%*A!UsaP6-hxIirc2cHI`4|{p-'
    b'mp_O_TMDTDs}=PXpa5%%dXc>e1Py~DW|UlBPvny!8J=DD<XSOf&XKSdPjG^o=W<)6MEAZfqArbq@Jy+N$glLTEr@#p&&wH)O(9Cs'
    b'uV7x)-riZjkLW)t2daTRXX)y!DfKr+s4(;bF-Wu)#Y72MgY>0QfZY8weU&9WQ2AqssvFdnm6=DJfR$^_DSo9l5I9v@MurRGC<vk;'
    b'dV;X2TG?~`M}dxv8hw65o7bMd_kOSpXsF_QzxVKWPg<?IkM}mMc+k(R`E5g8*_4K~3N5v&w`RKEN0D!7!G&j)jy@U<I6klVY6kX%'
    b'B_UOeQWxZbmTGC>=f>pqL>^m{VBu4@B2~d)gw?nJUiS+fJkx!<H|aZO$|<4)R%O_!$_kiHXshBEdWAsE3l%n?g~n%fdxO#dN;tj3'
    b'Xg{E>Ks6<^eN#{QE=&v0AN7<U5P!Iow`lEk3HNQ}d$`XZbf7PmXkhcTb9sxcpvAvNQ(qkiLji47k^_JOAgfdHw4HNM-<8!*n7hHf'
    b'51djWQa%bC-0me%ukw<wj7G0i7?o&lMG0zI(MZ}21ovv+%MYkOIYtAgDI3C+yjd${!YFFgl9kF2CA}?heq|&|wyrs;ca<K)r9I^d'
    b's*=4$UebyG2@BDxR3M6|7A>hInJ25!YuVsixb5Omqxq2{e}LpP52Y@x>v%xn{|U{VwDlIa=}50Vf1y9}@%RUUKv8IkW|&t}1&%<A'
    b'w@<6lPcB)HLf=DsFj&4TP^g=zzEYidPhPh{NZ6=Nybd7WuSyue?E&z9JRsQ9U&!^9fTJnyM`-lpj@}nR^h(L|wwkXNM&9@FQDp@7'
    b'`#nVZlx4gHq@RyP0lbj1CVs7)^oZ0S)iPdQ??mo2dhKj(+9{&GV91m(z2Ng8Nstke3XlZ8pu%&Un3LhCHy9*H4-xcw!gIpA0C^%Y'
    b'_jm)rC`AMS&%`1c_LH7aF!b`<Z@-b$!X$D8oXUVtMS3bsMI8TD_D%oK|NIX|!EK)=m}i)P4=^dC`Q7wtZN~KM9!Qh!>`Vcl2@*BI'
    b'(D4n>QfSg!2**sYW*rJVe{*K&x$?JwAHWFVpWk5U-$FAI5w*d$c_c_GEFqmnwuDw8=iOYVJ8h!bN)B^4RFVr5BFJ#P>l<{(kd(N>'
    b'f#?uG-0^Ki9Z4Ew=@Q~FnG>crlvE)rboBq>1d~QiaqKjy(D|TkrrOA8!c&Jri<GI4GcuJE1WrI+vT6<Km5?5x+VogOHffb;bwKLI'
    b'B`6wg-VD?PltW+8XFy6SDx4Y92TS@UC2|-oOe%OY!9Wcs5}GbhYSRP9nSg<rAoMb6fJ-!H51Iv-99)#X0pk!U*xNU4LSAHP;f}m$'
    b'Q=kAb@G5*k1Sm~XzChsSGoUwOqASRh`sM;UEAZy!ru`|H2u1{)DZPDzj65U?W)>KWi58W8fB-rm;N9O9hO!JUiWs$U{M!U~<<hK7'
    b'8O<P37Ai8J3L3m2`Y~bn{_iFPlFrMlg1G>7wJ%gWvBcB2j*mK3$ZA#&#s~Xl0ZuZxOfTPFz`w8q<(s#R7>yK;SkuR6628~tQ+v=>'
    b'k?y}g&_qnf&d<7}D~C}xb-bdzpao#h3DcHlkv|mn;jFUUpI|h9klG)Luu0gr^2P(c!;<-*ZwNx}{?L2-6Of+2ynI`8fWD$Hf2cjW'
    b'P2PVi#3(Ht2VFYe>YZ-+48<Y}UBy7*pa4Grb3J_t|N2;{pBisX_5Tm!{juaU!&SQ0Ocz)qy*N$ZTkw<V>NfGYnd>9|j;m9@rC3Eu'
    b'>frUi9PgaqccaZud9x1$qOxsL^MdaRMT<iks)j3Mh>_|1ZqlIc!>^%mM}tX0e{e!z=}v#i8~oj*Y@jvaCJhIf^olufwi-Kd$Nab7'
    b'6mkt1+Z5dN`<qDi1nW(D3a2<nBN9IQafR4B2W|ow!lb2r<Tq0nv{Wa?q;1krh$#br^dU)g9C~bIl-*+rl7h`?;2A|=SteMe1d1ku'
    b'zM;Y4CLIeybuZA8Nded<eJ}4fg<ehx1!~Vwa8IE}k-7<P@-QjT$fPD<3VRw$`jB8E_D!D(bw*WPGxl0&(`iiMN0X_kf+`spDO4I-'
    b')8~{*E8cyV2uM9XZ~vYRqv7KrJmUqozJ4R+EiWSAnTm5*DdGFwM6n{=JdKM4O{>8R`tko|UmiB~#vFC1@TwEV*0dKi?2yUj8||C|'
    b'9Xfx!z%8KSztm+eh~U+_z0v*~<nZOs&x|q$RT<)n$H=sKgW*IM_{&2A3P?+Q4+?%VD)`=42LxVK|DC=W+c*C7#qm7Zmcp`L+dP3M'
    b'0O|_5d(qG2fH5iasn{)|4_xO6@a*+RrXYurv_y<nD*bwEP0}h!Wsi+X4IJ8FGmTyy(_Cf8VY)s)%eHf9x6uZmv|D`ptetD3CH>KZ'
    b'_&1q{mZQJb>7w0IcKWrKfAF{tNcD3+B+_Vi(M<J+?_s%4wq0s=OO5&u2chc2_ukSa{m09K!j+>5b7fP8zFzs~&$Q7FNU5>!byJ)q'
    b'k=K*{X2tMv@CquU+7#~h2Dn9l$PIp0l9;akC8i%NK!BeCks$G+YqdMzbE^T&tx*DOA8F~EKrP{x0Rb^6f76anXr2%_RnS)xu>AB2'
    b'goh3T7b~aEfXzT~B`Q1H5oL%^sD-3pR*P#6O(FU(quobueN(gCZ`%#X<`MM|6`udD27)QKc|z;DH+bSix2$)7+Aul&?LT4cs&g#$'
    b'`c>U%A(l0nEGATqhx&dc696_a;ync`I2$m|J$7c9l<k8sWGltHZ?8Id9_~SaCm$6!g1l$&F-VGe9%cgM++T9d|Nc_PuVccG`~1{<'
    b'e!WY@VL$aIzL^LuP9%(g|AFf0`L+7)H@Gl*+QO18z>!LprNadH2+kAYcsJQvPW|*Qm<f*AQ;51grRv)^WebYh{Z!%*jj0dcbvWLu'
    b')b{~A#7l5j08pD(N_B)DMMXmYHo+84@80nx5gTK{N$nfQE5NHj3TTo5^lHAb+h|nb>2l@2`j?$tHJ61B_JL{?noz+IwZ*?oFF#O3'
    b'he1sVQMzm4M1WWJv;bZMt&x{5+Aid}Ic%y$2@U(V8;$PE?<OE(wL{HI06G8mL#+396u+BZapL&xIfOjD_3CS#=?@ZvpQ5h|_ygkq'
    b'(#-4S-H@JZ#gB1)nQg~!MlgMPFWYOkL7Mp(+H)_@<NJwzbej4o-}LeQ5gKcvkKz58=SP1ZXsAK)W90pwx<gC-ly%FmCVsgitXhEV'
    b'<^#Kh5z^SD74gT6j4%Mhj&^uPtzl@XpOQ}LNg_-M^^hg170=JgoLWMtCbnw0DM==!!f#TX0?h0LPF}7+ZnnY&68gyBjf4>-lBTU*'
    b'Ptd%rGXCF9%A$Y@9a!ZEnh9Ft@6c;$+lwH@$N1ryQbElRi=UJdRcx#*X`5sbCU#)(>g2tMS_%zIWO{<DuXz5hCda0I@R3n`p8dUb'
    b'NI#MNX-)rf_V-cy?`41gKTr678i+%`^8cau|CR9f3&yHLD#K*|CfxcFKK&W!_*d{Ez+4JI{sim({w%BSgT`mbqoIg*;qzULejmnl'
    b'xbO}p^m-)>E-!k#K7Sw>3cKNlH~+xzBT<jnSVB~ekm%bG2u^@b6!81INnP{R#H&35)c^SNVMW{ls;$B5A1@j;?cx$G-aQwHv^i91'
    b'n^YQVGa0<6Xlm_^8fsmCgBKjJzy*0do=_lQf~72V)*uCKff|1K0z1(<fXZfiQBTk*&;C^Eev;7+TD|V(o*l#QCjDHFVwkVoHC93k'
    b'^+pGN%%B~uRQ3(n$5upMtw6w)P~?s0aJ)(|jF*+sB%V5bJ%smb1YTtRVu%0&eYkJ}mlYlrP4Hm;^1mKstZx=hfBUL%l@AY*y)qDe'
    b'SyLsU>(lEkwFsf!`J)<vCLJ(1?dw0h|Mn}h{>O_z?cK_%BwUj(=1>f%jo!rz{$g^P0-m2}J-I-YzC9C}{|pg5{=*5*Hfps}7mDFM'
    b')#vxR?Og7ss258e03b?PSa$tlM{k>a*r#eputT_N_wr7Tum{z4-i`A6`~%?Z){o@5sb|5ye6bP#s#L5sRu-k7c+pW69GF_9S3~LZ'
    b'JKvYv|FZwf8V8$9+DTZGwh#Q}JA%^O&u0TtUxbzFC-0==`Gm1w0j*XW1CWkqi)g)&>pYWCCGvq<K?DD&#$v!e#rdm49{rHAF21i3'
    b'e-h*y)*bIA>VH{nZC4w%<2yoPL^qt%msd_-l0n|2JA*%h|NhhQ0nZA;eeL`;Cz$wnu-`QXgLm$r#H{y0<FADbJz#uT6I0^Hn}BGX'
    b'#nwaN2NCdH{QL7Yj{BnQ6gBy25k8yS|DB@K_Hh{!{PPnisWJV1Q1g9jgaY_L={=g#L(1x+q37kd2gpSA>|F(#8hO1qawL@6FQV<Z'
    b'{@tYFZv#^)eOzAPOLe$W61bp0E-!GeMEAr43o^ZQ;Zj+X!Ice#Fo%I(wq%Gl7s@U<Vns6~5D;u?aQ~V{kEJDb&FygsnMO+G=X+${'
    b'lTz5p;^H$6b#UJVWuFl8@-Ohn>-fX%RVE*Cy!`%p#ua)c<C--{^<SEdHA)5{2M8p8I&?BHpuw%1utgJAO~{v<qB#2A4OaUk{&|D{'
    b's~4zV-(2^Y3)ScnFT6@in-qQL(-X{nNB^O7y8M)FOv?74gz4QVe*0iM(c*s$QG&qu$3-P{`*s18Zl(()b^G(h^gl*hg|BbaQGzhd'
    b'*mDDA1I7Up*l$2WPhYE}QvyBW`R4I>O(HM^mJ}V|biAwSAM)_*N+%yIjcd?Oy$}vju4#Fv!<>XOa7@ZYLoaZ96ZkKfG*!ItiTL!b'
    b'dbOSYtp|Lg-E#N%>Xq8OP)A<bHJ;bbH)*ZZi{eD(f}^KhtC}Tg*U0_bq<<`t;18H4-Bbl3;I1>%M|V^r@U}c?G~bj#fqBwK3?=ci'
    b'*T%v`c=41Pz(2pKg}>Ym5JBEm<&CNrfYYaMBt`M?1M(=p>NzC*@Tkdtw}U@mda(TCMbluQ0*Y!c-}qeRt}5tbe>eRR2mnI{{~!MI'
    b'6S|NrEPHJ~C8wGZeE5n5z<Vg@`0ce=|H37@Z^g?{OPn|<!Ap0QD9=MTsA$)}VEqYR0NPoBc5tsRynB-qmF3E=u~?VI;jZE~wE!Kj'
    b'>aa50k%c|Te#FKBOjeZwI)P@;+>xh+Q$xrqH!?ED?(bjjxx?bTxZ<Rypq6sMD_MpD2}GOPa~tp+W?C5~@}g>`xlQe0r@z`e!?C~)'
    b'^$f19?(wgJcFK_3k4v$-@Fu@D$H4o=l=vt9YS(H3DB$rbQU#I*)2w}|2>lo77hqG2THqjz)M-W&WLwz~4#w~_G-bX~lH(<1(7)Jk'
    b'Reu9?f>9E1VI7%(H8VI;C^)q{o@Y)dA#kEtr56<3B%jql&o6ebY)ylYp*%H>*40Z_>Y&HpT~Vwi1I42%+V+cm*EwN}GkIJo^EUA%'
    b'&|CPvDg~%Fa8KI+Ru_T#!i{YWkYfE>mkoF+jiSYh{-ETRmXvKsu!X2h0eeCj1|`=xyuG)k9U=eKp(+~sDhz4E#yCo>a}o;gSgvve'
    b'&R_xn$%cd*tfFJ;T>l~u9YBy!?(|qvIprWxRdI$L$VXc{5R-@V54qKp@mKqVPoIV$HZ@n>V?`V|Y-PwfWd#NbA1VYZq5Af(=gzah'
    b'm%Z*;dyQQdyWQra%QrflRSscjs#^r{SODtI9Tc?!%q$pqp06P^7*f4$`SU)3WV8Xl>g3To%D@`lN%Qzdj8JD&e|?~yXTfNZ$F);4'
    b'ztSa;gMJ}bPdzdS_2(((=)g$f;tic&?EF<E)LoMjAk?eR04E?2=HW(FU{=uCwI7G9ex+Y^SCKM2C;%1ZDKb#QjXGA4nPp_D0UQZ~'
    b'^Qsd8F;Wsva6$VQS*TNo3UxYw3{r8?a5fqI1T}n5bFv613#Y$H%FtKo3*@SBfp5}hwG9oG)f*|XO0nfUTn~rF-qw#z{Q?Kt160yX'
    b'2-4M$;ei>2d4`ArJ}FJN;d8IY`}g#!2Oe!6;Z3?F460Tig5n(9ANJb7ezDsQNU@BmJrtC~Tk7dU1@8b~p~Yw&+&uT!D}CHsp5YEp'
    b'MoTE^j_MVG>cAZXa4Mk-0#rNnk_A%KMg^Pyd>7djOxdU^Odq=-I|Lp<bqent-PZ_e=m>BNt%oe)AadyeQi*NC_8r9iDrLBHLXSZm'
    b'ZGXa(G?Y7Y0qGI|n~(beey)=$Jr@*hg;YB$;2QKReBZcBEhcy5`IeS`zMrS)nZb#TVvqoivlVzfcSpU@;ISn5^Yk?zUxlYdG63A8'
    b'gz9M(bf|XqR7z7*QFsdLujFB{g7@-{A9%MM2%h?qzRKE*eyC}C`#dL9Q!tR=`Jx|Yk8s&kNgTBozX8)wE^a~8u{eH^b7~`Yo1SQZ'
    b'-n^lwg=Vc{0L$~p$M~j339zgv!E=&A7hg7MVnYc}DyyHef=;Ol?^u6q(E+c+i9Yr8JxdL?0cJ(jF`y46R>|g#v_+-*)$YG3Kcw&i'
    b'hV&O%?@(Ks-~b2)&y>W%U`*8>9iu70Sg|+pKfvWbl4*ay^AG#|TRH!wO#Q#f{V!(v|4r7vQYrW^^7l)XhW{epe@CU_zsdfuRyzKR'
    b'y#Lio$$ydMU#hhHH~Id%DmDMbG5qC9&wrEWU#=AWUCcic#<%cBnehk955T8_B-QjXCrL$4J&;>4de#n}aeMqp$Y1H@m$)-fURDNd'
    b'ZWR`_3J6HktI$^{NcHbz3FHI|TD>Dht4_251?ZffGhdj#fD8_JF~w!Ux8ZNqX)TmA2_`p+{2u;Vt6{ulRqGOJ#^1!?Q|%5XHLKV5'
    b'4JjcIDy0DD6=&bz%>N`;d1Y19D2Tw4kN8ycQS#Y;o+-E*2MpDiN9|2bYI=dQ0iu!&4Es%u;6Kk_33vh;XP(~C<OIx9oyQu$FThJG'
    b'xC>~Q>dQ-dg%*xW`_YmAJhM=_w1;ZZT2ngZN(5Mv(rQL3;C`UQe}=m{bx<6rBA})~bI&HACNOOZ<O=LFPW?|Zq-Ipqv)6cE0~Jw)'
    b'Z@u32pXaJWDHj+5QBaaDE43cXoU{rtMgHS<+GDjN^=FFAYCjFC6(QioZ(2Kb7MtqjX8$O6N<r(RU;t*a20aKcLd8Cn6r;z&n^K@t'
    b'0gRIW437hNH9YWU1Z1hsv04;R@?C|g47|~b>WQ%Yar_%>@;|@I^_IWy_xLqV|6^-o|2(6=yrTAxv;0fzaQ{5Ff79ySKhF5iuKE4r'
    b'4E{|kh5tC;zp%de-{SQztxEpm%>Jdd%wOa3Kez(=$nk&F$6sgc3+tx;1RFoI+WOD%^Ox3W{|VOq`pWJ<!QIcV2mcdXePtE-FR|iy'
    b'v-E8I)T?smhjN}8QO;MYi_9;7{;nPLRIf$-!S3Vd!==VT_2WGIUs<ny#mpyb%WsDBy9pkkL-eI&$J@=yJSDvTwV`*H;On;ziw9i!'
    b'dDhoIPVxNv^KW-CD{J-It*3x@l@6RPg9Q9TqYFPO#M~+|__uNqH~gU8G5>t}4*n1P=^R#44hDU^$2_K=r%~U0Owb>mKi^Nw+q2pV'
    b'@9;pA&icO<a^HB4e{-pja>~hg{V_bX0q9IQfDb--|NNw#E(xR6L*3w^=r3k!%9;Fk?ae<yKs^QZ)792bM)qoAKONprF5G|8=l@~v'
    b'&A;15lKjEn{a0|@`xaysN#Q0bxB882tIGPeZFwcRkEc>&a3mzQDN;?4w$&d0?;8=B2_#N}6m8ecZojT7kp%LLj4LBP!HGv~naB>#'
    b'(}@^Hueg^9Yq<l0J5`MZ^sEdOq!AgFlV%MxYOYNL80QB*SqC_RE>89c{{^fSD*_G48Xa<oZ_y7{S(FFDdvW&m^8EOPM45)O1p|eb'
    b'6*h8?X<<n>10U!e)+cxH!KbMl1?G}gH;~l<#fc*T{gjQ!@`_5aX-uvua+4N^olbZ4X-}Ksa4qzU5<vt{JQLZlgnJ7Q{oK*cFw!C0'
    b'*NT^LIQ*^Zr!wZEa2##pYw-LKrBGK+s@xv`{R4YAn)!D@<Rir%)=7zdQzKF0ehKcJ-LTIJ)nSSiLEQ4$90-h!4BxnrH`$s*x1cA?'
    b'_f%mjT1k-{*U0khfE__o*doVIz%Oun({n)hGVl=3U4#GNr<^Pm3WXenI5$)or6?J>43HVC$PW==LG+$M+KDyk3Br+}IkmKs4t4{5'
    b'?3>=wlqy_00gaO_<Fo8{{$|!U|Ez%B!~}2Ez3+E^0%-*5(N8~p_=JA}m*bg$*@nO(-s92{8IVxSjiaiOTu)*e_i58REo##+(jGRQ'
    b'Ok6O^KNU-+ahR`WvB6u1NBJLnmoXJb9+lnoeEP37n>}>6M94B*w?FH7ag>Q1Rn|-s59?p}9`9Gks8YhCg!lojgjEc9-sQ<>AK}yv'
    b'JAZp2lPo)5ew)YZImZY-n<I+Jm#>vyebqLmQ_2;Pd4vMOrz&n->s?hiV8j50(~Y4SV-}ZXzL*D#1p-icSWbv4G-ClnQ6q{wJganj'
    b'5I+6RN8CQr@VlCL9d=xR3UxKA6OKvc+>#aW9obI=w9rqXO?v&x?0WIPF3;G;c4o7|icg!GT7vmZUU>Ar^6x<Tz!(Zq)Q*A{5AZv!'
    b'x4ji1ST0N$c_U4EgJy<;8UER*T0N=3wb+`trHUn_0+oSMs~Fy_{biJvuBtTEgxiLjYhfB9q!?~or`~q`N_Lg(2-S4a&tZ*N<I*&f'
    b'OPY>^B1*U96@RtW%wnr<w$g?}y}#yhVLyD~0`;(?4TlH!%jrjH!}0+hro;QXQF9lgJ(7QXKT08_Vucxsn#N?!PiIkxbi&)hqI&Hq'
    b'hT1Ke_n9>>8z;~QWS{A|9AstB=j_u!>aSZL(^~!CxNf9DKJvqo4xXVX)Ki*j>{lBIrEiT*ZKj5@cvXBR`Y-s;v<*$Ai(WUn>S(y1'
    b'4u0CyGT*}On%x-bwyDz`xg0jyTB_lW0<nBOK%=O3Bp@rOn%K`rC9AN(c>DeG0Kyaj=C<O+v_)}a-~zIUS-hUjykw1-iLnU9C~^RK'
    b'+A92?+??h>6qzzkor-U}^e7zogVo*r0mnrde!iP2U?ae4VR&Rnup#2sP8AR#@!ugr<bLjIg8`q6hS(p5V)^FbPm23gfN?}h@TO4)'
    b'fwJV6XB-no8xk-~{*`RIPSIzN;PPED@FA|@9V*LR*>bN~erVYtk;)n9iF9`!q>j&SuQ<qxUK_iF^`O?O^O0&_FYA)S4Y3}g7|(M7'
    b'0Em~(h#yM99a>X1RPC0|*LMRfOh~0QXkTGP46R`7G@qDC+WV4Hz#%aBua#6-keO8d@-v!e(uoBcmN&(!!=GfSOHP7Sf|4JV>bnAj'
    b'2+D79>EQ5wWj);T@qsNIa-=4B0mugNVe-ET;GtUL6&NcCjh2d^$w2@IPKNwu8<!jQ1(8cg`34d=1Z}zxq+9qBHtSAF)hnF3>kY$@'
    b'gg`g1(4hiNimJWQ?)4Hq;Z@*l#%6Mu12(5S%Z#?(o@qO_edm9k-T}FSxg;=Psh2^*?;96ObrLny+}PoO9;Y@1iylywDO7T6n*fG%'
    b'I)~B0v=^V=Ef*iBXr93<?+HX16|fBND@X5m>|%Jy6IG%-UJT<SRoTUG2kyjG0LqJGFMMYzdOrfa4sT%e>)=3kkQ{In-hl-69X`PE'
    b'dsgQ!Q*Z4E7`T(iej=iipr`nXTKumkq3iJDaEAD|U<Bld`wxwr3gi%2{}C)_cd7kD$lnBL|FF{?{?z-wU_JS`(7Q5x)5DW-=ZA}A'
    b'V7iT$cEyIfzkT|-cbK&&vAF)Z2$Dk%Ploi6b|M$ArV}IrZX&Y;INsg#hWkF`+D{kBb=ucf^Y3&9F!i5%<)PlQr6`jvN33TfraQ?T'
    b'DtPU<fy+x;j6}5EVe?q|Tj;nz`E%G2^~*QBagV+WI9*CX+QSa0J`^at;oV<PFTKl?^EX()&U<%$_U7H?k=_AH?+n6D*5DBIP3Y#R'
    b'L-k%eAmA22_BRRq1;=Q0dt`KOSF8Kv@Zf--64ZJQX47Et0HW142jTtt0QPWx^Dv#`rr}}Qj4HZu_@bEY;BGo!uaH7)XY-uV6LZ)p'
    b'9Ns~O`d`rko=x~Cm`1Q5T;-WF77=~GIf3K&nf?TeYT-u%IF-{F+8~n>q-^QSgu&W^V#1O2DB>d;h!Ncg{-(jwcmhq47au@qceFsK'
    b'9z6peJO0hhlHsS4Mp)#f>F^uZNAO*ed+8d%ehrjGslg1RF-ahLFM%Q7iR$w3U9=7*Ry~IlOUq4EDIFEy)(tlXwJu2RVovWsRM6>u'
    b'{@S2lMx@Se+_DzxWdM>ivj1Ks%P$fjk&Zyh9Pqt`^@ZLxy>gX%r!O`LA<z+FkIU75XPwBu1f9X&-QN!oRgb$K;gKo->v~ha%31ks'
    b'zTx4ESI6fs;po19dkM=nn!w}T0#N#aLcICK>ZOo?Jj{rZg-v1O2xz_;6EG_kpP}M&`on_QsQyQ(PZ$hFOmCZp1$?_AF_z10r1t7k'
    b'j8XuuC*2ane1kZmY89ewGM%f7SM)Zz*^4(+X<dSHYan;8bJsHs4r?uNqBwQ}Q=f#)o;X2ZyZXq9!q72n-_%(Unap-v!=FS3^DW<x'
    b'0^NlF$K%MFSm8t~9-_vP>DSk?CT;eftVp09!0MN)58ds0{vmJU7q?8fTkyfcReM>PO)F?|vl`#I;&8jjJ+wa}KK;p`P|1h+79Qge'
    b'z4_<b>MH+9u~i-6vF&{Hmt4g<>i!n}{M!)zh48GhtV<v7GAIuP2%Tp`>O+U$Dttt++_3QFzZZ);{K6ROU=P)a1b*EmIsslOMs@X%'
    b'-{#jp^|j4pT4crB)G}!z(@<xw?^uozM7n7QQ5XOL8ir#6!Lo4}xMK@QHjWL4StH#wN4{Y*)13J5%y?vuv~t`BNHR>9UQ#7gIS|he'
    b'L(p@QY^b7GOLpBfo#P!6D{>HQ8O1-{U~`<>f-@|+XCcrjFXoPCdA*v>hWM=)FBf+t^Ss$2B)zwb4fM&l$lFeLAYx~%+z$Vqw}fqW'
    b'@n5}X)GO8P!3*ur&=-HO%m33WRDqy7VE$9Z`K0-!)zxas{s`qIt%4#~GJQbxpQQ^gTi=Cps(Q<w$h+%qGY(&1E)<B@f{$#v$Ig02'
    b'VBVQOpYxk3zPKLU%pK*cc9oYS6F-&phPp+;lks1rjZ|aHx53L|a5Bx-n<y<;H=``xwh&OLKICLju7pUw^ifVD^hqPUqM9yEqvM4)'
    b'=2gDOHa@rQmI+2xy&73OR{qLIijnkgT86Pyy}hYG)D;dw#AlY4u<XDulVr-!H94LVJ@S!k@7;eK$!@)T&w$U)YS%5jT%iSPvodLH'
    b'NLoE|o0Z80hWwd5@I`8I2hv8TEX65ewI3mT(#YpU9DAsHNaTL>0?+A&1RlX734Pq7v5OU7+gV^`rdJ4U;U#w}t*z?1JL+95)$r?F'
    b'VI$%I)9FeTDQYcK)Kb+e4Ls_@TjZ>148!2<Z)~iBdB8xcC=!|i;^RMxcD#+TXfkrFE?Tzw&JEY{C~w1Vc_<Z<%Lpd7t6e^mzSxuA'
    b'=79M0zDIDUB3aZO<%SrGa_o9~u**caF{E7vQ#Z9y8Drh>LS5)}^D7nfQ5h4m#obU9Xgwc;!Z1>^n(|Q_4QVh$-``gv<~LoL8U@2i'
    b'mM@W)RT#_CS4#a9N=Q&4z_btbwxz)AKI70yVN3|=AKqR)z`xf^p||@9E8+c%)@pBimHyIqKHnjrqxMH~k>E{o@~7<YKcU-F6P|ni'
    b'40g=p>QFsDdP=uQYAp?&3UUlf-}6EpPdhcQnWB!z)6N0(nl6?YFcpjV<3Tns<?rNA*)_k|4q0s$%V6=P?7}>=$jxUZqFSt1m~)>{'
    b'x<S8_R`1X^07O!~mVU>!EAQ^JdLXEce?;K~_Q#r+E@Tf2tmuF@!1s4zlzZFIuJ!|WvE?4Br9Y}SFx?(nO<*(;CY|G6_Uj6+^mf}k'
    b'`P?5m7q}ts-e^fD;mNG=8r7{Sm=>^y_(kV4mAaWN79SE3>Q0p&VZMKRae47!dapExx3l<*--)IPAwi_k@|{n&3*3fW+nhjH()l-A'
    b'E;@9~hlOZ(VmPD%1lkFIJnHBj;qD}ss&`_Mr#&S7qP9AXtcOzLd#HbpS5`sKO3gD@hXdn!t5%Vi<h%H4?G~r1QlM6)31kA=aJ$K<'
    b'&6VRRs9_2wx+DYp5sk~S(vHCX^{#U|NA_}-Kad=5h)&90I?DdMI-Ka&j}KF-ICNPb8;=>?X%B$jgN0g)Fc;!c&DE+RJsP?|3g(vp'
    b'd+4P~3d^J9VNcS{PL$?xIS<kpAyYi8K~!a7@Donz<R3+2z#!2@%5W>h-{K^~r-EKt648IE<l$x76>;T~TZ{1Wrz8*fm{N|6jr}Rd'
    b'oU00+ZIY{x*6j*nxMi@so>$&+y>PJu?T=!gXoZ7~EBIGTfUH}!gZ%QeX|MH;$Rc4+1q~ECyFT1?WeZzXBycnxz|NPUN5a3W#2U+>'
    b'&2rvwB}s^Oy0Ri&rLNo0slYO9wpa6YgTtL@Bvr!|C8C+CY6hj(Hy}%r$^RNAMmU)~hO5Lh<YLO8el`2r3;f8Nre*2!%mnX|{mmiV'
    b'{JDJCwy-`j)1yE#FbyAeYnOe=S9zq;e$Wy&c%_sS<mzZz-%kXW;(<64FBN`mjP({%Je1@9!effX7rB1FwhhykqoC}RU81y83lFDt'
    b'RV*+_Es9)Yt|}b7KvuvRRXG}&o6+RUqvk~L-}T<Zk!y}9E@a(~=LuR+?s}O57I=4SN=aIIsL(Efo&}NfH7;EY?M{3t4Yi=RIs&WO'
    b'uJ`A!`Ho?WhX)71AJ8>2V?2!WK$6A*)xEA7urQIjz0C<??N`2%oi&ZW_O~o5x+=!MqEf_e5xYAR6`D8R;tu^Yc&!MErIPHzjSEjm'
    b'Lr;W05wi>lf~6t%oUEg(Yh@+L5>Y<O9p%3je^OmJ)%g*0nCV!jvEXHY&vjn87j-g;e_sfb3*O^MtoYZ7EF&QRw(vW_P4LeY=&t08'
    b'=3+SS&&!DDnSzm!R{s^Fkr{I-@Is#Kgl{})VU6sp;B6Mgq(4h<tbvsrQS#dT&H%*kU~;|3A*HKUJ1!hZk&tgG(hR+yY{l{Mh)%ib'
    b'AQT1+iu7-mj4)O!X?Gv;d0(6|`;B`xH&y1<_!8tx=L*XHdi{;Lib^N`YPFmO<UOH-Mr(QWRDY_8sBHLPJWX9A_#yv`U^w(c^_`ER'
    b'^HWTx(j^FkN16czt-r!O_6Y4CCa@ES-{qYAf)TmJgCfrYB@868t}PGeqa!n4crwMAKhr9mxlj=pnFmJusP%w>V;J<MS`L^l(BQjV'
    b'L16i1sSL3Eq10QNLtR@U7|ht~+H7XUqWG2x%(WJcOhC(wnMYmC)Y(be+2yN~b4|ISfz<=4E?^m_tVJPYw54Xuo6bRcp(OOC_qU6A'
    b'N;>{}wYZ}QVlov3Vb$<iS*SUoqRpA|hez~6W`hjjFEP&H^z33_x&vL5P8W=C`VL3XF-8;+9ZhA~XZSQtjz0qN5W46gQOVcq#{1e%'
    b'n_;XzHjRUH@ODG_`gNn$8s07zz&+CB7-GY{E8h5Zkz5M5+h4x+^Nako_{C#Zol*r_&2o4Bpfr7XPh5yfSflLcK!)D!B0+Wb&JTqr'
    b'1)&T)p47qP=RQ^>;jsC~DeT-Gk1+d!i3+dYKlhHwXL*4$Ucqc|#^>+fzCAhjPTv0I^!)7Yo0GSf_$v?89`MfbG10*J$-A?Q)628-'
    b'zvEL4849^~e!+*AEKUw?@%HhcDi1|@;p8tc3h(Xln-hHRex2N^t-XKioxa2$4AUxne|&j)^5z{)z|g*K3Moq-5*|yo0z#uOPGB3K'
    b'5JjRAb!5p2$WxZKtNdLK%qWSKilwGxhFL5Znz+8QZ2kPQr4Se8g~FL&=I&CI=gPIjmka|}OW(^SgCDi3z>QR@MAI-o-_5dR%hOS{'
    b'z{Nm{)>}E7&exx{)<SIK<`%#c`OO-fNKnY93BNzb!zj(lIp&R$^S*qgj`~+$N(~8$#P8g?S1=Rt0l5xLWDwHcE~hY}r^y|Nsi!?;'
    b'l{`M7-*JS#P|th2S%*WB`i4}Xqq~_JRIft#vtIj=@qpP5PW&1Ddzj3?X6(9pZkR*e+Bi_&H&|jjX$<K=5ld)*`LIg&dgWa@-SFW4'
    b'E#`=S$wL4+m(4EKaa)CY?<K3neR)4g`?!Fgs1ycDp6<zK40uLYS|Jt{9!<ZHkY>c8MGS6oi!MqDmxJtqe@}2Zhbdgn*G-(hHJi+S'
    b'`s>;GpMQCM_E&^&QpWJL+HQui8MIkd;&8?8?lJJ1QpXnve)|%H8P%!k_Bwt-5775zj`Pn&kWt^uG_9<wCY1IG2&|j7f>E{A5m6jO'
    b'EMm(tq=%#jd8fw_y%H8K=6D4e`u7+GdBhEm>Tob>S-Lv9n!GWrZmHL+4k_c|;hgvbO{*E>3?r0e_IIHJZqv3K<BB7D<yxp486LI*'
    b'Vb_G(HN}9IS*zBJC<d$(Oj|F(+LOh=QF&(aEs$_p0Dt0r^wm>Q*%uI5p9jN-w<uK$y?puF@Rpz#cqc(GHH%~T?MUWRH@!!DSbC4X'
    b't=YU9{+HVmyy*x<yq?Z+;&S{EdPn(Iv2`U5OteB5*%>ikX&fj8vAV=p+JIk<3nVUhd}Qj<L~qf})f7%HI=hjh;NQqmsBgj)NV_3g'
    b'y{?#_eCE1EXEc2lG7MtKF6*_Ba*9Ml9^ZZJCG*J@TULiry<0WwX<YN9?JeR63hWItH}Jh;;6l63O=!><>yKY6;a?$7itwpcNL9h^'
    b'yblN<4k8mqvGisLA%LQEhP8-M;?5qjK#(GYfCyYV;%Dg%{0k8?#n;1Zv)~E6_!j0)-+|>%z>4arMqiuIcm!;p5_<yVhJYw7kxtQB'
    b'BDw=IeJ9Y!b1X#sOw#TiA840#n`trWsS_MKAC{8W05w=;P&>8e@a>MO^i?cDZ$nNBO=B2h>?n$lA&0)alAWV7IbD|FyVG|kjgUEr'
    b'K2zTy&`b`;w$<K#MvX<T<m=Nnr<Vw~(fd|gyHzw)X@6t?1FPG{GWujLLCi}Nv$*|S$_B29Y<fx`CGTm=*n3a=VjP>=Rdkd@at#r3'
    b'mxHe<{MaM*B>q-9t3u)l(U-fv_dfaD@(R$~$G8{7;{oCyrnA|W9Oa&{pNwW+qDXC2CKX!0<W?WA=NxtU)}nj&8a3!|KzFr`EbwJq'
    b'fcqPbSP%Z)%3me?W3@(Akz6-{@mz)JaTZ3gsE!b#u&-L*ln;1_5`vll7#OHm81RpCy}3W?%}{#5$yYR+OmF7?Y<O|{>*?D|)W+mT'
    b'gz`{7|M~Rw>+1^JpWqlo2t%4WAQQ}lY)kx@BR8RI$6H}h#FFLsC|hZ{SgZshvZ5(G>tKJB)wUqqotG?F-=whzXa{J|vXC2k7@m4J'
    b'Ti=|{lY^?uX@M}6zBau35KR$N8ZEKpC~wrO387*H(4_)Wm3vb1?k{u+$U|Hb?wQ3eo>PDC1oEcmU7lQAzB;?O^t^*M0~Yl`UM;YC'
    b'l-kDm*%`J`u{2)`u|EVu^a+v7Wac6g5hf!=>%04;OB3j|%jM*h;-yQ`#RckD2LzynBp{HI#q47#5R!s>X}S2dWHIofFVPBjOyq1H'
    b'GVi%p-pZ@oKJshf+!j!L%mG`4+OwV3_VHt{S?-!c9?7HV`Ln5?2s?qIa~H_AX8fFE^WWoai(w_|=^~w6%YGBbGrw-#^v#1(l#V<u'
    b'y~;OXYCQireSJNxJI?S$(}sTG*W%6RTb#|BF~a#QPz3FZx*qr$mV^E~OdjrL)A<L4yq8mu<cr!vy1f-#to1Rbo~nYM$mFX#!7Kqg'
    b'iA9CA#lf;jS>I>!L3Jwd!~Tv%?eGgn!oLfqH|xbZk%uD@@C_JeC6=@*4CR{~gs$A~t!OzDH%)|y1rs(kUz8KbkMS;%b7QbJ$Z-3#'
    b'0REefmB1$`1uEO#UhfBTz;cuxu?jhN7`{5v;d+krhibFn^}<NVFtW>M`T*TEpFj{X9^#gs<C;G6fR?|H#mOH7O#PjcM2Nrw!&4w-'
    b'g^Zr%#{y3+hPC3FCExc<1k*WuQ&_!#sIm}wO*bA&#JxP&BCi@7Y|${%c@q>RXP>;Yeq&!XR3TU(bgVEzu14%0$5hpSF}w&p(AibI'
    b'08760J*r?pK_b&RPyv%busjH|eB}q$&;6QWbErk~xuC63YZ{gu+Udnk;c}+glTJWqtmvxdqv^GCNU6^Ft~CC#%a*I$1=Y1u&>@fh'
    b'H)S$i>6W81QWXfgbf3mC|L>Bc$cr3@0Z;zU%EO6ZQ^by+MFWmY%7dX4EcRlK0uurEERu+-eL6rD{&tC2f@Pp+g$i#}IfVJVFp{69'
    b'MX8w*xz#wdr~nV;vkxe44#)cH<oG3u1#$1Ag?zo5Tc^cp(Rw2uB+8zDe8G+Sy7d5Pm+}L+&VEQ6OV^N!8NK;!1zI+ib`y2yt1#C~'
    b'T^06!bEg>+tn5Aq{>rmPoBPaBSo>*a5%Dlp1&{N^`N=VCK#GC{+kV{mz=q-F3I6fps~uO%@nq+1Tav)Os&`4h-b8`OAFBFGBjqJM'
    b'bl!B@(OqGPjo3EdlqCxuwR?hXGncNdhlJQX-Us$jU+&{ks*3OgRorF;el#Rtpqw9oyw}>7r+i1B9zOl$`1JMDe)jp@@x{f{ue(eA'
    b'6p*OPG2jZRiz2&DT!B%j9Xj+dE9rZg_zGOOV%3W1SFJKIjYcW-SLOBk+n0G)dka?f`TMt8?u|U4Xfw7r?nKku8Ey)#rL1_|7?Ug3'
    b'y|~Vgh?7C(L83?(Ua7n(quUh<0hMtx_yrb8xVvAa0W*rvH?98@iuylU!Y2;*r=R5Dd0Yck$vVWy88yF$FQvu<9u8&u8K!Xtu1s+I'
    b'T4C(DT3acp=YXJ<np^n?F3(R+ip||l5p0yaTa_)>piOURCEt0mjjC~kKu`#RSUCtOLDL!Lp3ZkBpRMX7-Ai~}xsB%;orKWD!}i6k'
    b'_aS8q<!{32yF#;BXvtyc%ZJ0x2Obj2Rba{oB)ye=WHZ?GC9j7pZsU^ZgO^oQqmLZ3>T7B6GLo30pYy@Xl>y}<7>5XUi&*JW$09ZW'
    b'dcBcrg(E1_v|K){*^|rXC@vv_r>IZ#DE2jt$~f%k8}7En$b>)ia4Y;Iwd3orjTOF2OCb$O9+93M|8~J9xd;a7MZ&94%=Zv+!|N%o'
    b'B)_fT2@2`HAFStiUB#k<v$wDRPVwD;Iq{CqU%WcPnid$xBeARN+n6Q`!gn4Jr<zel*&yMk;=qq?7a_$bm*RtAis|I9uW;bk#G*qr'
    b'Sp{>O=`+=Jol&5^m8+Z<an1?frOp_Iud*Uv-BecPuqqH6pY6(oXxTct=rS~=6juziPLY1}VLFdAp<^l)vah5#RvSWRQHH=-p{ObJ'
    b'Ae!gr=2`|&Ym)++S$=)9jYNzle?E<QbQE84!5pQuxl-liH3f$+?-4Ww8G_vItVT&jBTpK+7>p?U3I=|?fvZu89WfGr8QxMIk#uY0'
    b'lE@U*Qv2yViZKA(%L41>2`V8@@8u|t95b%tEd^p*36z|ajJ~Q?@bojGeN;esVc4$J3cIBS8Z>RLn;}l1XiCJ216y1ma1V#%Ck6AL'
    b'YkHn*p4G`}-_~tN(7>7J{8{F;l23>g)#Oi=PWDVW%HIR$EKK7%U1YBLlTMz0wKk@=)eg!iwvw)PT`Uq@=(Ye1y#rj@|2_;n^2Q2s'
    b'$b}-Rb{k^BC<|YfetGU&-iN9Vnuajo;ZnoZ=T*TcU5A|2JiaPn&^*T62ugBiyW(H+t$TmD66qma{7c)fpJsNFu2jg7?e%yvskr`^'
    b'S>NSE+G4tMRo0JUyQdTG=A;%9&H$+mhf9=6)_kw(So6b7seUyP@Wm}D2uRsS{kD`3Zh08l)`<>>DKasAEZoml=T&fDPpz1(PNm2m'
    b'&l#iF6<KZBqrwusuFKuXKPgSr!oB21C)TDw`3k>PWjuc29w65ik0oDC=gE-rn6!F7mhffpt?HNDA9bGif^*}TYyipR&^&`iT&!)>'
    b'Ew<RJ_j%y|6aYQtD3s2A!+UM`l8Twwd$Rd>Y{jv%XL@z3zVjj3+WVH<U5v`D+tKY7@PFQ_6}hXHFEJ#2qZ$5ljRUiU87VQ8w*l+O'
    b'kfKm$5ilF|oLqvpe<xC?*h$qC%3EI5lHu9!h|&x7zX(`B;ozB3lc}YPrCOJ<zAU#ebW_<;a9?J&7)qal&$P;|S@fP3?f)(GaB1V>'
    b'-4MgTQSDp7Q0#20N$)?dHX)DYt;*E!&GPs0Q6kFbV(BUHJ8w`cWS%KrJjxQ|ARwIDdG0Uy00v^ygdNRG=W#E9{E44p`H6&-$QIdl'
    b'<7!dml|~OcTcuTDfPDkdyjUBhQPuacp7O?3#}d)gInXSaPQs_Ps07@TU8vp+1j$Q#QhgdZ@9T9#YpU-xvo_N&uT@k)f|qEVJa>Yo'
    b'?c_79a!$hX+niD=w}Y>n@QK!zwU-U4l-9TrDh7Ykyd<sGG*<1=x~lOQZR|}U|H1}uv_&gm6t^0&aKO<J|6LJJQ31LLqdvlaeOnGE'
    b'ZsA_=%aIqn0?Z{ad;%3BC(}lh9Fch=?pI_jD3Vb)0WX*>0#T`wC792bR+g^;cvbA-v{hbdMcE0M*kVbZmn+TCb=S5#*by&#DvLqj'
    b'H{2K%VGOdo2Zx$Nwu^mU=L(AP%W@t-nDh>}s%TSV25G<P!kr^pr6K7&2Z!FNFnNds6=ZsThhMeM<w`dF^dhrL2Za6vJ$WGqHX?)r'
    b'Ds_B?;4TD_kqo5dAN*VEtCy(*ELi$eRjkT&b;TytdrQ-5M#&dDAhsAi7lxA$7@PKG5gj&P-!WkMjAIFw-TRe=RfsU?{z)QMkfi0|'
    b'gN-3$`LZj#V6hlyRe(x;y%nmhGA+N9XIj}fvKM7R6`{*duQxS9v&{;qObNy_{g5vMq#m5UD4~LzZd7%mmSw4HRh&+$gQ)8x$I&|Z'
    b'3Nq;q@aq%JFm?E!R@vp|!ae=Y7OYbcTFGK*qsr%r6k$9|d`PYyXFzz5dLRo1@C&2s@`Zrv;HUDbbRjUEuh<O}6<5J*fGwiXC;mt!'
    b'GcCkb7A~rbH>@pGz+$LIuS$`p9+47UXShkm(X&VN?{6yQDxI!E*7rNP8&K3=_OucOcja}3)&`c7pALTG3%w1?NpBs|zrV|JZZ1Cc'
    b'Eb})=#BnLUXxC{GFtz4MTlt!{?Y%gAdwG8R;u3wR+!(DX+AA_uIj*HV=~)2*wNBVhDckL;MEwCn4uNaSpn9<DJM8lmqoZy*|Mg$M'
    b'5j_tL0?#9^=y{0d<$2nF{TH$mSPy6+1?&~uGG$2zj(>;O!x~^r1_&hJ4gL(PSEF7AoMj0*a@4^RrDDV#I0orDV!Q8Qn)v}CFOo%1'
    b'If7Fn*H<BhOxY;--TK%lg_&SDX5q99J8u`b7|=9bDbf@~B5^c)^5pf&ug5R`Zadzalgn3UFFoGJ1tz&yBTFB=VM|=`)k|c>m;TMW'
    b'Dd=EJ{u|EZrIev(up+M!VB%F8d<2gt7c2kay{wpiHa~-X;^4=i1fR}nf6qS6F$xFvU*qkz9e`l;h`g}l=r7paG+fLUbNCIH?I9i8'
    b'Im0yYccQ%Z2?~MNegH!B+YA&hlrb{k;ug-xIrFK6_#&aG<7~Jue9$jpXfX`y_AS!j#d`S>XfUBQe2wP#@$+L!hJQF)3Y2MXveylJ'
    b'W6%2?{KeeAPi_~hcNk*My$LU7%wHzw?BfEo`wI-jdrs&0cupR=a{;UO<0k-g!lFx=KyuD2R=$S!XyMPfPKMVxmzZ*XzL=q<N8By>'
    b'9gLpaG`4PVtc2uj4&=_iY(9bCZHT|(t1nsXgAwy~IujIukFzBm$#j8<_K%~*{fd_U#}ECrd;-S#lCAvd?1GmY!}UfA;3GyBa~v)g'
    b'N%DFcGZZQ>gz^33XMh#8X|a(o1doxYRk9gJw=QpiwE0dDIx-#JA3yxJi{+g^`^BeVoOeD58+xAa1s+3mr2G}HAb_Eu{6E9gryo7)'
    b'Gqg5{uh4NkjzE5rtid-DqNVx6@oaV+{nN+V?r%h%<L_X>iD%@nvBl!QT(IQrVs$)&sl8r+8t`%nc5g~5XLCBTobG@8G%gsrI$4Ay'
    b'b239Ho7e2d4<9aYD(52o@E1G_IAL+Ne+R?HUzLSSq^9zIp7@}X(!!rmA$z1EJRI}Y@p^R&n%U}M&*RUkc@=da+WKtNnQF*&DSi^4'
    b'KdiWd^&WKC8AvBkD5r1&?iQdPszYtl&*KJ|>Vq%VFw#33B_AZvEql%Ne|T-rqk6YoU|1n8xPYh!y&h}vJY+*V4$;V)u?Scj@iBZl'
    b'@WT({jXxvg8*KXrTE&cyua*zhqZOSZk?d=XX;~9|O7MYq>tHrbZb?8Qfi7`_{dq|#{iXxs_v%8Zo#PpvCsMY-`M9`Ud`f=ExG?n%'
    b'j&8c4;z_Y~FQ*Ba>SrLc)^OC3+b-|E?+{OcIZXYT@{Cw5IIw&}-+-C}+><mkpf=9tPgj4P0=HSOaBAcj{!ZgXLK8o}pgN9%01316'
    b'!oOq3A^Ci`j-IKM-)(?z*(c(xv`p`o(}j8>xaD)sz`~g4_1bSbCT@)}m6a&RLyEy;8anzzzT3b=5-BVQTgerJ5iHip>;X^5%zt3f'
    b'k2tyS=RTLF|7Ot(e>Ou-Ec_W5YA)X6+exx{zWUw+B&T4NsDLefgKPzkC7oEZP2SJZ6^5J!#u|OMVgB_N<DKu}5W=Y5F6Kf;kkL%z'
    b'dd{#+&HDshDWCUqN~M+~^r899tINxG*^mmh59cC+Q@mQwqa{d^#V1-=*x7hCy}4bTEzf3A)7hx+v*lnx{S;bRZgh%*Fv9?~2So<c'
    b'gZ$LU#|2ZCg5`&e6<P*qwpx<bM}&$7g5s}|rFv-ig?4__sB`W&X~2^|h@%6*6po)C|AN=>V6&khIu}_RKWf0R#MAkj78HBo)r@G>'
    b'`3d8z3*!9wdW8<$nSU?TU1ALU?)Jxw9c0a)*~6#BG9or0n0?Crq2=Ynk0uDzu%*4i=>XWgq+G6Mmc{5V(<LJE-LMAT{M!#*{BXPy'
    b'91RB~$~S@0K()=2V=QAPI0pW1=*ABou5>&JT1Awn)0cSe{(^${<nDg;kmq+lYP_gursVtSS2kzdM<SfYAS{G`P<n{>GEf1WRT}0m'
    b'v&ARXk|YI~I}YGnVe|x&D+(_(hNd@j*l@9q_<GS@u&I|vjP1oOLXxo8m?4Am9z+6{3T4^)jYlH<(6Bzp1*2C!7-Z7@R%eKP^C8U`'
    b'$`r1RU+@bQrfeJqK*E?#6Y^Y8Ez<8cy4TZSNz4O>LpGwkl`M#MVccG<gS+YKI}T8B;5`RrIKAZK<_?9)yv!gqzT?1z287O=<oN=`'
    b'bjZ~Sx+vgd+;ud)Cr?BSnW;Bk`quNf3xvl34f~(`0$$}K7(wx7I-gQBBU>_F2Q#J2cWjv~=KhTAjpYZnBIZr)ZBU7t`reX7*AKr&'
    b'UnX@w^SmH+TudVt7Opvd(4ZB?xp1r$jgBrm#C<Ea^yA0<LW1_5QE4VDy7?I=@P<e3{X+3pT=hhkGfZfs>iIo}Ews)zz%($2k~C4_'
    b'aKE_qL2Y_@d3Lr`T(ikLMkUpyr1<euAf+hPImKN&FlW3L;Ircg@^W#*2)6pik61*?Jogg@>-!h(Qz5bT77g*4|CvS4A1)U&P^#u~'
    b'k6tWh>$~~y;E4Xh7&%)`lfSTK00X}(&^*5io^vk$<H!5PpJC-bSW*mP0Lma5;Y1;n{}&Wuk9+bC?1HI3LsI%3ja)9UpaELo%o%q)'
    b'C;Zz_Q_w5fjX#4q{vO7T0#Ry6uNOe>XniHeOYSdQF7D0*G#=iMWjn!^;qQcOQi=Y?UoEGfPr+<hA_L??U%1^b1ajz)9&YANkp4Wh'
    b'&e0CTH~vaN4HRdD=KJqpyk!fKj~gvt%A|w|p^<s|@^>QP6_Z?bJBd3O&NlEqk|^eE$s;y@FS?)@pOo`>fs0aHUc)UH_ryZDnsT<J'
    b'56CKi2O}59jhkKXFuIuPdXa-4v=mC`;s^A{50(=wQ8ebGNP%;)n$Bi|GPrh?S51Bg1IMUD)zka@7^BldBJtPE|Hx8h92g5&=f9VM'
    b'r(Vgz-FGV8g(^tCNa<Ze8}#u*?_ppz<=PMa)ah~vxV{L{7Ri6<N6hNzcX)b?{3%P8=}8;baJ<u(CvPuLFHgyS{h}e(Y{^LmCMo+1'
    b'oCYzHLs-H$S}O=UfxR^`A~PJ>x?@hF$efIH#~p`$7>AKNw)Kf?j6;{1krBCJ<m>t<^20EW0xJr~hHFQotva(DHgSBzVaC|CCbq#w'
    b'V^g=81)T>huwxdE92UpXR*mW--E}O()<?!9FrvsB1>-Pwg0W$Qy6=WDizlJ$Lc4|)`??!V{LwgYUCZ|E&>F|vbv6!R=4@h_(FoSZ'
    b'w%m!u^oYgA#0YezkDO>S(fyFfS)){)(w-4H?Y3c>6^+NP6Ig~58zaMvb=a@S2&|DC>+vWy1H<=qgN<zib}E=Sv2Be*Q`bWlGm}k>'
    b'ExHP#7#lYOX4|I2%u&Q9q3(<=XKdS!Jz;JTL<TdrXwsjUt^s@QPsX|dJ7bS*Xk+4=fvH<g9Jz52_-+t8emDsNphPnsJ0Z>@2m-_M'
    b'w^^vMWyLyd@+h`oHFVz^JCV-<OAkWJFsxC83m1<0Mx8UB44fQLG}-ju=ph?^4zZB+{3h9Mn>3eA{IO#*!w$`f9|1j#1DnCljo<({'
    b'u5Cnc1me)KLVs-NabQoP&~n|#a`edrhT6I#I6{u8N5ObBiF9ZK&Z*<OZoq&V94mqoF^0aw)`wIZ$Btu0j&H?qI>v5jOnhskhqht('
    b'`q*_R5e(M0bvVMY1xsm-fK6DAGjZVX#*>NDx+6AX@hBP_ksdgv1uSSX9)&CneN)Fn9M~h@VU{uB+aq~1cLu${#8b}my_Gmzz)Imz'
    b'QDp>%r7{GU#*&4&cgNct^4k9qzQ*sU9c^OzurtPZ1dJ?%QyRykARf7qYx>M)Z~_eAO+e}6N$f@ruqI;yq-h(L4ulbf_Fh&+3)v(#'
    b'V|QX2BL<}6o4|#_aXc|xIKIGi19K9N*qG(_atArPubte_`tPR|Er8XUOrnt$jC9+HU?-8!vQZG~47MsT^dJsR%L?6K62i6tLysdk'
    b'_YpA037q^rtcS*|F$31)jDdW76Sgd5hBb*nd?Ic<{NRozKvm*2Qo0pK@H>!sc<S-vkjxK{IeWXU?QU;rt`*r6pjXov+d&+~rUf5u'
    b'&>7$W0UwG&X9ViQ$QqBvVQ9n-8^dzwfeT!B5}C}>cIne_Cwc^o4^*$%bZy&@nF}&+JT{%lI5JG;JB|)*msXrtK>jw%{#d$x#H*S)'
    b'26?HQs1TaK!gO;q@?&5fI%t`&M1BNnPZ;PRKu5k0n`F8HY@BN_S9imSxic@*Kn#t1;F!)tk9FUMJ%PV<P<}#l9E{B{j4TEk)o2s('
    b'FS*%K+=n+i4NUWO=-7`(6H6aWLMMuxN#IN@BN_v%uwzgm+_3{1Sm2Lhpc%t3K_dj!#tf{`2~B6WUgHRqO2+`T1XN34Mm}uFDD+3R'
    b'#h4L~Mv<ulQ!v8aT6Y}RG8xEx({fx`T*t9TW6<{;9fZ9Tfi4}yX6S%bVa2fN6Bb%lz`_`gr5ladj&rg`Mi4P~%*+@p4r4MJyFp~y'
    b'?nozF#_&fVCL@2`>Zt8?lZ60a7U-$4l|~#fv`NeeG*{U6afExTgL(*>{0M&qN`!v}PV5Gt*i9@K<@qDJwn0-InV`?Zf&+7dwKjD#'
    b'H1tsnii2%hx*dV`ABK<U0*)#0v+)RQFxv$(Hkk{y2<qTK#>|<RP6&$q*wuB*2a^KKLwy43{@C(?9(31uMAwE63uaAV^J9}m4j7t|'
    b'4*Z*q^)bxJ0p%GspM}AOjlbvDTwd}pU){3RH1u%m{TsGNBFM`IFfv(eg_a$H6^m?X0y=?Xg0(yXV=08a8T&q1<be*xp2gr0#p6ln'
    b'TSf@%!HM=XjFDy9jx(}+-3eI$dgBDP5e*cOgky6OPuvjxYqC9cH;!P}87Mot?Sm;`j$P0rZ4i@=>&F(b3(Fn{u@#R&ll5cZBzg=q'
    b'8U*?XY>AOI+0!u0*fD*}az^8cJBF!_7-(5R6in=qGY)(_qF@F4Iccz5&kbwrG0H(gpp6J4dlE!;BZGxQ{_RX6nqy3K5OQWbadcP)'
    b'(*ivZ4D&Ile*stkflD3^%Nzk`h-|R14X{4PxSDZjgXzChr=cB=p+#8!&<X++i*6hnBik^eAar~Nwg+%=$K0uL2K*~RmZ#gUHAX8_'
    b'N1fIJp{MKNM4v<xJ9a_(#gSpaan+5$G<C~B5n+O9yHlq=Fi$u-*2IWmactmjV3vTkXO8qS4#bTOkV&k~)^2~~H9r9J*#vGh0x_f`'
    b'=MEw#7{Tc>f|yOlIFbpo9n18`FqX)1fel-(ADTAU+WNSCPb@Y-dD78#2tzB5$G}pJ(ZmK#p6L$s$D9yUDYnJfElYRCppS%Tj4&5Y'
    b'UTBPB9kyZu7CeLL0IRYhP+CBz1q;*%10n|f#0E9ZHQUP%%|fS>jl>+l*)}KW8!%ie3`XGuM(x{UHgZ5lZSo7;^DueZF{&54CJ3Cn'
    b'1t`jXL?B9;cVJJ9o6jIJBCr{($;cnMvFnaw8%(*-Hf;;6I3K>pon;dp=s5tgj=+WhyWAf;Km`^|b)RGLQF&%j6dCb^jeH9fWsnyJ'
    b'*pUu&ZtJ69Y=9;`+UxvdeH;PL&;yVf(HImI9SF{67AV*-Wz#fl;2;rjt}q5pAH|^Yj6k;sUBDQbBV(Uq0g4AxZ8V8M(S+sq^%3fN'
    b'NI$L%@)D$qYZ$@E;nai<cA3}se4Wri=Xs?&Icq`jWOf|5=u&s!Jo+QBtV6?(bcUzJ^g}TE;t-f9$T-7xCZli+x;`*MHjb@{-CmAs'
    b'j^%<?YEGh1XGC&3@Rb;pTmw4{;RCANW_$msW&q!qSU#E=u$>@B3_V02EHi!3GXh}Efn!fx=367jv4E|ZkpZ@H;KG8!tn@9$Zo{$w'
    b'U)GJ-g*g~{gi_XKh6Us^8iAGpr($A{H=X!9v2z}WvGF3zNEOhadpzhGo5Yr3qO$~8DQH0<8^ORqSJq9SY6B<@45a|hGaFkYVBzq5'
    b'<cy4oWy3K9onj9|fGyA+CmNY1kTU3DAQ{adjDZV-LKZX7u|cGmM!1jJf`|%1V;@DXs{=tt_9Q|VJ#+|@51|(@H%H6_3k@{0iEYBX'
    b';aM;uM=-$A9yp5@xxg1gXY9iw$37gX36LdNbB1NbCg_EsANsJome%|F<jKp^<6qyNU0j~NusM<-hJI?po9XIy9UMrQ;p9M+JmcjF'
    b'STuaNn@PZ2peOOI$Dhg&nIv{|rW|;MXOYtS6~;uxW4!`urt3(uuEolH`t+$xe((6RS!XfBDwQ7@S|fy!go%0>W`ih21jQ6CFiaIb'
    b'h)xWrgL#C@AvDD?<Ng!9N7Il)oTn&q$*tdA`k!(IZ8+{?H98hNsv=-DHI3JtZQC}wftJGHVa0TWb;Nfw<SqCiKnzTT<=kQvpYLWF'
    b'F1~=pKSKXid01Vgz6wEFCA<QP98Zc4PbE@vRaf$LjvilvCEwoWax6HQd~Fl$k7BY|s09HO5hqN1C4dt(rCtk;wosvEV|5oT+nfxR'
    b'FrI#1kq)+4lpqHG(0R$0i~zes*5NmCodpHiJR}{gMcDat3))=g&i_ELVnEoUy<sPdnZ)nsN~5UzB^?fa2On<MGk-Zit*}EV|Ia$}'
    b'1wC`X>E!@xt}kH$;`N+PduN&uh8)6)r3C|INh9DZO(l}<VLsE(N18nMgHRswfl|VSqr^p&AU$8-X9bgnA^)cLq_M8j5cfZO1|tv<'
    b'$@YtaW62R}ImW31h%2y<d8ss|ng=y8T;F3bVYez2p;!Ir<{r6NW{B2}1(y>Qh%nz2=K>d($H2wC^OJYSrveqW)eD&f;3XfQzdn0@'
    b'kq2*FvKet<93iz-tma)&8&$qj_v8?h%IC6H75|VNAt+&=<KcOW5A?BD+k#qwLR8mPIu<2F_|Hlu3duWRnAvGd!31Hkr?5I4F}|Nw'
    b'%_@~A|3l}T4e(h!U|1xKP8mUjcA`bNrV2H8_&o;%1eufI0!9q|WB6l+CYT);Xi$Q_lSIjZD5ir^U=;U);0V1IF&1+IrUGiQxG=@~'
    b'2_in#vmH?#E|`*6F!AnZ>%>#m!87#?Om+6)xlWPYRbmy_z!moT9oy+Ozgm~|0`Ho7<-5Q5!02IEtJ-cm|91y}u5CJNRszD}K2x!|'
    b'x;8;f)Hc^V!7q1Q==3`tK{bmWu>`iOERNvx={UMeS&<6ie3z2x0pn>by;-ZUrdZ!;9Zye0ji|h=Gy^`Yemd-?$r21SC(>U||90}S'
    b'yrV5zxhfSoZJaNx&6REUI|lqSYMRKE7}>AqXYb!#Tz$AkJtM8m*sTM??X~Ve?Au-AaI4Fy_8RPrt7`ITF_JF4bKjG16W*^NGSHmF'
    b'k8=<Y@O}LutREO{cijnW7+nKmYz>000Hn<+VF*)OTcw2g;jOobJrDv|<Wj7&2dcRTI<glr&|pQyk}3RumB^x*bRdcxPkEg5lYE&~'
    b'-gsXsez2I^bC5i{=UNx^#GB4**TteEUH-J}KiyGv&}Hm)_1CL>3u<*BdJ2>tv4DzP7rm*4!TMt0n-H3LV@LUQI}!~ZHkB>o^wTu<'
    b'A$$-W^m5SYVt0-n6~WVR;-rpHvqDnuX*f=g52a~1bGbDuhbe360yYfr%iUqe$nl~&a{gL*9_Q?nAS6)<C`t7@Z<)b6Wu=9xPopp;'
    b'DmcQ1W7+QTsl^hy+ERs`>S#2sfe^&~w4A{}s8dxn`!?f)mtNuM>{%HBwUlbPpahsIN1)Zh30x{NUae@E$$4ZLiduojvp6h`RU6b*'
    b'sIG%qte|;S{9=eY=4W{{uT$oR);A?-Xw_9O(J;$~+wP@O-zX2ez0J>N3&mf-@>(<hE{Ocj@=#s4O{FGsbaGffGpW)w@ugZsiRwxe'
    b'Tg?)$ls=OA+os4wfpNF5Fi|-sdZldXrKs^$hD^#wauPi8M8O$PBq_+)hv^;0IebiAEIY80{mPAev1i_P`lGbc-~oItCpaouo7bMJ'
    b'p{FHND3+;4fim*SxNhKpO1YS<3QNV7R#thbrhFecmYi)`A*HLK=ZajVG+J~4D!#a_Jn^C}PTrAM+h%P&mlgwu#=6>X^YWm3pdtP?'
    b'SKWxkhG=_Le+jyN_aQloVjz_ud54)01H$2j9#pQY<Z6~>ZV!L&+~J(vfH25d1P~XhtzdTjYt3d49jSO~kK!F0mtAgUk<B275i2Gn'
    b'yBAV+Brq5+S}xGrj0L~u9#4JZrD$jvMHaKgChnKj)NTDy=W1I5`434T*V~i^da})iRoQoiO`+-<whb?HR2?r^tZqGdLzMGj@j4n*'
    b'qjLpZ^e!px$}R=#D}6ii5~1I*?QAD+79eFm-_82`FJ1##9x3JOrdO&NlK#@%ZPA3LR@lcWC6sn6yYF|>`y#zp81IfkMX-4!sk_p>'
    b'3csEC4=Ho53l2@<`4N9L|0KW0xyy9CQq%diQmNF?7#}F!O*OYAZj!PcQx-54RK+d35;LsWP5D!O?P|QCLOSd|Da$a}!a*i}GveW2'
    b'^>W)=As@RM|4C^hql^;WiAF2i!IRcJlC7G<dEs*8nkrsqrbc|rNs0!u8Rqx0ejp&W2L!V=$Qyg<&?K>LF_yYE>(@W+q<#ao8tLQO'
    b'&on)y_4Lb%=Cj`l?e{8G%YKJ%5kF=qhwvC2es>$BnU5-C%yG}cZJey$OZu{bPJPfTO}pQrdy1;knYkHd4IE{EZa<yJi3FwROzesR'
    b'Xyq%QEvvy5-z$~jBbQ@sRbSUB-4+)6FWz^}BE0HK%Lt~r+xq@yiN#Yu|ASvaV;7~Yv3%hgp)hXROjWG{4U419@A2j2aOk*oicl3Y'
    b'xz4MM0&mD+K&f<T1qgxG+n~nCUh&SYs28M`Al8mfRs-8XTM&K%#ci-!to+%)RllO**SylD_(twFep}QF;dNG0jw_4H)1#H7BYr6n'
    b'j_u^E(ro-(D^Tc)Br#ug(O9t<a_P}*B-EE&!HVZf<1+2qr?`UtMLL=earZTj$N(R-certp_BB&uWWU#y#mH&jcG;JP(c5-y-Sdie'
    b'>zd6iUV9~+-}Q5>6bxWHNH34F1Bz8b=Nx7VOvxojNv3#!pTMyDDShy;&?<LIV^b6;knl=M6v2QHov7*hwBVi8zQDr8*f6w<hkv-Y'
    b'a@HH!dycgb&DIsSZgj*?6KPLHcoQb>%hGlq!3%e^DQcZhQh&xjs}-RwobQzkMqvVF&wCXcsCT~?j`VI`_hv6zzKcdrZr(R77qZDM'
    b'%^424r7y(e+xW@0b=rS#H7|E~QXfQ%<0Bo*hC?NYqp5#0UnH1RXM4B)M-euY^F{ErWXZ-b8ZpRMrx$QaPG20q<^f<Y&fdH^y#%Va'
    b'onT~+!%<|9!+11tCw@3~ZRWTW%QDT#cGzfQO>AH5ZQaM^`3craw{1O)FkLFLeOtHO33J219l0iBp=;?bvweSJ8c|aZD=-Aom^L2v'
    b'*6)<UnkySPO-|>qTBxp86;<zdsO@&1k=&bw%IOuCx2wAMlqjNn9N~t*q{`+*R8o00D#MY!Xm5U7p=0@;_zHz@lwSQ>dQ*lKCh$=N'
    b'<K~)yIl(UqL(a`>I9;*3T!3EV1}TJe{QC9TUr%0oFJ2wL{q<zK-KuW}w{FsI>lzzr5qG30A-8GuGcUlRl~{y&Hd|o$XDF&bUiUj{'
    b'xKl&tO`~7mbwB5HcieIwvGW<XsMY#7TlH|feGhh#4Z>oitT5z-Nx4TIA;E|<-b_~n2*xY3EBtWw-~|YuS-y(<RB*?p9mo}L3hl~A'
    b'@6yDe!NMlxPh+n|G)F$-6Pr|mJ=0p-vR$!a#gNY4HusJ99E_7VfM|ZnkQ$X+&H4R$m2{N?)cNZU@x0PP<`l@UX?+{j2Te2#Gyk#`'
    b'H$k;V@*`A1-e_M7P81$*jSHNY;OT{F8lSyE#m0w@@Lz2riD*)wF~NLz>zT3DM`Qy908jY>>3Yk=AWa3#qaec+G7mr9uIC>Tbxk&j'
    b'S6Ge@x!}cbGU}ES=(V|<ts;*rT=R-p3VzR;o&<{N!bkg^uDCg;4X%kOZ*i)9+;XC++_bLSHj?H5<yxV|xUSUc3tBZCfn%-VW>bn='
    b'Oz7dc3He>U?(Ohy-SDavMSPKyCC0yAZ*xtqG=>=ixwhJNFE|aSkd)Di6c?|MjDbD$DSfJC^BE=N`jOkY?P8ZGqp4N74b_H)u=%{y'
    b'pAJ)8EF*^YIm%UGta!*NMHF4r?Q`2$x#nn(K1P6vQBYJguYxg<EK@`~W%$um41_;KCuIODo4v=slB^I6>7_sTz#i1_I{aAR=UWCx'
    b'2=yYh>+6+^_EtEyIlN!o7Xm!;)^@gvH4XR#uUrUy#$P~K_L^GGwxp)zC8N{QIK13eR<}c*I2kG;KtbQn<q;H#nN=Zal_7D$m091D'
    b'>U%iW1oJHZL^_1X_j|Ls*No~KI?js%>|WP8KXqKYW%ESA8{6l{KW*LC8(PoKLPN7t0(0k%7G$?iHZ$pn&8mm>?cA3;1^Z!blnloR'
    b'C@_s1PT3$s*R*PZ?8pI0&#cj6Tcp?F>rcumjG7)-8O_&}Lx)XJa`0U1wN`o`e{I;-LfA0$o|2k(+(|e<e!QM_Vv3#1Vlq4T%f&~Q'
    b'bZEDg1l2oHm!<Q`Pg0X+xMf((hRLAyY?O@K2rmdJ5K6f@Tr$k-h99uGnLoYr?qNI(XSG-+_$_HTk08Hxrqp3kP)WP$KWdc9kVE{l'
    b'Z%f3*sCm9v193DnGenAh@hNWr?I(J^#v@-V`Afl&bdWa0!x!dPtq3Ct&vE;eqg?r5-8te7^y;1Ld6`vVji_;)qBX%HNK<X<0GBRH'
    b'o~Q{FJgl|+kTmJh;?f>A8jJFsszB7b(dMP5LTC-w69pY#?IzH)mVMNS{9-5ht)PXk>7(&RMVL_hf|xgrcfzSP4j+KfFlmeYQ(v!J'
    b'+_R*T<2!}(x21fNAbGwFLz~7^bit;6Flh~nfY3A+RAJ3UhP;!1jo(yOx~!TUmL*=DcLV$fX|XLic9l;=@rw03O3Hoqb(4<-FS3tX'
    b'Th>q78Pw1ykWZzvM;X@jm2ussMLH^Nn=}he;&G9#LveJ9`BNmdIFm-XrLbw5bQ<xAuM57aT`SoGfkp`wjqWerXmtw}M~R0}lrOBS'
    b'?sfUIWhs#V{!xOUhGVEC_Lv*lI<n(4=y&9>GV~oEI-AZJMQkmjvcAOw#I7_$*InE0WavAnCYkDWSW(;AUKcC7wXYQn3$~ob4+`w6'
    b'9J;`=5EH0CvcOu^6jgFFU3DnN5>(<9!nvf4J<CB?a8}FbDw^&1N+=Q*cY#%gCwRMPHKi~y!_M(+))9(Khs3&wnc>eN?~rgc3N*%I'
    b'y}G9eX#_9gXhEXu9#4$Xx$Q27BcXXp*Okb$?-2V5q?&fav+iffV6|lAcN+X#>vx)Otp@{m<fp1Do@*t8JMM@av99Q_FLL2Y9ft<|'
    b'<qd4cPd|P5gnw0~FR1J(ZKODl4QwsfXIUf)^5u)$8camY3}bbt5%U<L-mi|tw>^wef^)Wjzl*3MSn^)ECE^q-#aK$OjV54ehN7!s'
    b'NSA~dq*KbWN~1Wj{~AZAa?pizr_iNT2|!{ek0^E%gVKn08!!3f`9T7-yn`twsa0xfMP{?<Hd`D3ZdK+Lqgrl|=L7q;3hS;K0zcw0'
    b'w>00M>lmh8V3@n8l$zX_fzRvs4hT>P%)LkGnYGIa6RRTAYSmiFxO{}bsPvw5&tT@&#(+VeD&=;x<lzp+`hk%41fOe6t;{xz-)0Lk'
    b'ds1U|wG1E=t;)!;EElfo!S+sVwQ1qo-qduR)uUtz5q{HA=S!pQs4n_pc}JzkHNU0JcbDqU9hP%eMIX3>@Yl$3HtU1g_HSs<)Zu?^'
    b'+9MjOZ>%GUP`9zgjv%?FX1`wHR$n*m?G^4X&*@LMmxuAE`&Ie+w=_X_V-LHfGH&AMl{{55R0=HIq=+k&>xRttV$6+<wjp6i^4=5S'
    b'&K@Wli2cb;0Mrj3cSG3TKaNkwSbeikJPY|^w-h}fZdPEMyM<5)aYlQ;YhNImKQu?Ac$j6`Sx5`s2p?BJh$=j}R>y~ibVUD#mHn;y'
    b'j5O$x8{(K?d(wH;x8Ek$TUr}p>YXk*DE^x&NNR0UwF<ud&A1W8(?baB80znFghL-rjVFLM`Dp?@oSyoheW|pbqqym|zC@CGn^Yev'
    b'nQ?AI&n`Hl-1q%bG7V-t!8qq9grR$gw$N3-mGBENT|o*1u{By{qs{mWYRf`id#goPyu0;MQpN&xHIUN(2VT`x5`<iq${)9I(`MIa'
    b'-h2(Vnc|BjS;g+|R}cKMtRgm)&EepLEczdEk5(z{iV=9Ziv<#SxsbfVt-$7Bx~_0%_UrEfD&pigM%&lx|6j8HZ<egFA1ui-i#p1|'
    b'+m}ogi0>D-6b=7Eh{)#{&+RX#@IoE(d*<HBMT@5$<Km;R6(y;>V7=n89f(n%U`g-H4>Yaw?394$hh^06NBY!`Y4w2%(t3Bb7ebLy'
    b'!WlToFboJ!UFX;7sv{<)^)@*bcLBzvovF+u&OFC(QfLX&Z)#T|n!*|^5;!Iwr%OZ={-XVQdim=8b0kz`GCo(&zm}<V>$OZrvsGI)'
    b'PRc^t*_r5SuhL|W^!A{Wsy5^um0#Co>Tfu6jUCjBabZE?&UCpyxQ5-zM#VTh^sHha$~@!;r!4sMXO0dMCS<_FRM?A0+~fmT$dxJ_'
    b'b=-j(X2+7_fy>jmkK+f!iKfd;*VV+>u+&8sBLQTHx?hnffh4_`r{_ml!GJf^<6oY>eR=XX@0ZipC-hsfZE{zr04&fV1#lvfduPx8'
    b'53C|K4F5Sh|2vQr6;ybZf9&}6<;nTm<I9uc3!q%cS2Ex4I)KH-H6FsYcheh=slXQ=3<95{4iEl?B%Dp?x{uu+!9RU|b5THFPbWt!'
    b'))QJ833-h-ahO(}5KWTTK@BED3W49c;_d@@j$f=Hp}6anxo}qlzokegMXg+;B!h2{u(5Osy)-Cch$YF@h*|7kLspqx`3y)!)b^Sa'
    b'v!5ILqnaE0_E+gm7x)sYzxMjRth6kq*fFgkMkEb5x1?44#Md%`t;g$Z+FZO!-<;wAjaG-Omry0KU!HC_;Ae}v1UAC|2*K)RQ_$#z'
    b'f0TPRv*yJlRcVChRL+P<nv;bZO?U}x2rol@!or?SLlCji6eLN4URos6gssTS*(W*dcPL)3v%+#2wByWnf?=-3%2EIi^4b#)(R7B9'
    b'i=P=!_lI*3tvOUc3^opRHf%3c`JtXMf5{JZze(U#-Fm_*inZFLQm9dpEwA?q*H`<CbwLH9(uyka06DoQkD&EEp0tJ&QlI&=@57M`'
    b'D6Bspt%EkUBhU(yWP6&;$DM4@s>Ed>uRek|*r^`0S*hB5g`Ju*R9xwtIP`N4_1ILtO6vQTHL*IJuXEiR8IsCE7O@Cuz83|rB54LF'
    b'1+1`9T%XscZ%-~L;~Q)E30%iZ(7bMLS1(zN$^zbNKcbjlc3BjKW)MbHmD-KQrs+ljmMe9mcoedcJ06FA5ROdKv?oBSuI(F!9ogfN'
    b'X_&4RL_5@})pR46jF=nyP7uaH<hzX7BR3o~EcYE6BiC}nz#K(c8AGuIC$t}+PI9&M-4v{d$IM?d0^PS=Jq%q3#t``KBw(gvP4tPa'
    b'$HsUZ1VD0F-O;q+_h>YVbjOO~C@{x?@A%smzth}!0?QZrmTN|SXzNiBhlY<8EXNaj6dIQ0+jeLL-=<`13`FYMSo|&?PomJWM!G#>'
    b'W79EVy7nmcbw4&^+cj*{4x@?h8_c!FcBqFIJa5PCdkP#N7C$iKIARl^Bxo$Me9MnvlgG@~$FQ7c5Cq?|>TobJqe)=srXBfy6gcJx'
    b'7CT}vRoxglk!^;$?HF!gVDV`;bgWRvBHwxxjr`FlaChnyn#6SuCjKO}Txa4K6BAFC?V2Og58xcdw&{$6-*5fbcrwAV)RApRrWJ&~'
    b'A4a-~C31mYV>bxlRK$AZOeVH9GW>C@J6N3@p-9F+1uWd>SOR9VAd1*Hm{_=RW*it}%L)w`jO9$m@fbz~M_47RaJCM-a1E^X4g_-~'
    b'E1K<R)wHo5xN$IXCa%F^7y<KL*Y|ak>H651Sg-_9Z2D|8c6HxkR_sS3mpMRLaMnz7vP(Tl&C!`-1W`B|`4eko>9&hSrpK0HMHXnX'
    b'`e*{G#K`qG(G+?GZ*VD=3;z!9xj-H*Me(ma5fZFVY=;5xdf=^5>@uvsYWvI|MZkn2Q;(yGGm6~N1cU$#-PR4?o<wFa)<Y*YV*k+t'
    b'2u8M!m5Rra?T>V1yusLIf$1ZR4c2-M^@%fPu}U&ZolB`WB#5$1&^=6gJs!PCnjgY(vTP%a&9QFz?ifYDgfSOujRwIa(%k^IHL_rP'
    b'4c~F2No*i1Wl<CdAhCAt*s)+$Vh~|w2#ai+<9IZVeB08osxk}4V+*?WW4CTm@JQYJplv>Qh^=-baQB0C1giBuh(`nIV2*qpPBm;0'
    b'Xc`8n23VaNlm^?iMs5tE7?@7rfW$P+(2uc-?Z}Rq38ZA&kEu$l*<%LMX$-8|a`bQn;yM_OTpbH58z46#2HHV5vFlc+EV(?2w)IHC'
    b'm#cFuTtmV^)O=EJz?|@BUIO|zUR$T<mQk_PhyC(>%?KkOSlM_Cn#nkfT+18<a6(`MK#~EaggyvG;IyGR0p2!>u=spnPjp9*u;_KX'
    b'pHWyNCt%Eo^gy>_3uO)n9Z<V;e+;LWfu=SY+s=5jk;~Qa|L-9@i2)gmS<GO5=$fGmY)7ArT}wCM-~q7$&vp$b9Qk8^Y_gDnxQHUq'
    b'1zn%%peTW8+w*WD$2Tn30A(LkLC|zTouBxQGX`dC*|2+{;M=Yf22_1m`UIPboeF1QD`#&Z27{o{QnQ?lGjERJwN%8CJkW?{87+7O'
    b'6OUwqQ*e)kK3H4)v^;1U8fq*YgOqgrk#B<*;j)R%CS%~KV*}KOk;OnMj9Y-FsWIokjbPJ^z>fpwK$Ax3fIh%LTM9>xZn~qu2Gz2;'
    b'S;d<|OMwC8Qy%|Sn#mT;kUyZ%2#&fMV~jg!@)42BO?sFA-tTzu{~j9Q)PHKU%G>mM7_t<^Ol_D)%eJdl{iHtbaUWHz+X0kqi@KGe'
    b'l06oRYy<At7GPsnpG&A;g}2ddR{<8*R1@q9AK5`BR#z{4yI7shiDcTAJg-@XmiUBKMS2BrT{lnYy>AU<*MvUTFT_3P_{HHC$dLVt'
    b'W<>OGd+^6XBSiu|Y>SKcbu-J|5H`_NOb-k$kZ#P;$EI!@6Bn61*!j#f{7ARQuH(cGD0glYxS)-L4Hb@k+x90eXn!ESCt7tVUw0P;'
    b'unrPu2Ti-)-_OquXWNx{cU!zzUA21id(Y3_zg4Q@7VEc&>|7ZGa_>LP7JkI@cvp$HTI7IJLI2(v(xU+aFCmYwyp-Dm0G_xUsTPd#'
    b'CS(Kfom$#l9beu3N*NaKnTQUpM@ZWzaNZ+f=vpDh<rlOLE3P!OvS#{N$hUHfd%%Btvl;)baXv+ev8vT7Wm#`M#a6wTtx?@t=9>3A'
    b'g^qUvpKFU`*TmQ4f!}X6<8she0qVe?Ph;-0Bm9|9cq8ql*R9?fIOOvC<Gw+M7-Y2_?pq`7OAZb$4+Mu>mI1<1=;ihpaL-D>Z#C?7'
    b'GyL1uaBusAcWV#lmfNAj7VvG`;<nY{v~5H&;~RL`8n-N0xMNM(a_OrXnu82cfmVJ#>Xh(xh)tyLVS8C}9A=Gcp2oA)Q548+AHseK'
    b'^9KpDm*%c#sBK->ZhqR<^Si|3m1|geRq%3Mq;fMTTf>!ndL}Ajk9pMbBeM|{zE=(TlE%t&j-%QzebpA}mu-s2VLzs4zYOc0hMLP~'
    b'_!r-6@00=MBh2@^krmMuS<fAG!L1k*7?6+I=_>d>spM10V8UZjGpO)1i(jT)JtEucv8r@2B<NYYg1oYg%EF>s0r=%&lz85dSYWN?'
    b'uFAYRK5-eKLPKh`vF%KwbjI5xmQ_ryF~4j(-qU{I3#>pQH#Ey6qmO9{nTS8rK!2d;tBb}y<BcfkVf65>%dx-2uwD02&NlnpP%*bM'
    b'4T`h&CamzoZ(HWL`ox!#kJM1OObFzJJAIp%?l_$q0l$-=s2%SPc}h8gYA;N34p8Z4+d-aGbDmxDdh^6vqf4|x|7<=6mDrz|Y07bC'
    b'Gt|#Grkq6*R#}o&mNKCxQ+!_mmiPPA#<XsZY_H0CR1zFN;(p@*ugWQo)kNPeolzz==9408JQCYAxiL>NkC)i1fwSC!Lw!RoMf*_M'
    b';rC%c)lBI7vz+Zx9d~9m8}om8J=+XM5RM0Mi-GW8s3^`Y=vMW_s0f4w6vGBE!gjr=P98qQjXhMIj&F!oSWU)h2zd>E*d51kUq$A&'
    b'hBV|^^BfmWB-*7>5hC}MTS&QLwj6^R<0W_o;bR?uyk{!9z+j+i^#!t(6|5@7S4h5{eAOHn(tw6kJc%?{ne$nR!dIo*N{qTf25a^E'
    b'RjzmO;FWPL+-e^OctKg?eplU2Vo45V%!^EZMH7K?>l!QeZARy!bw13a;iYYBaYcE6;*<_8n$#7|iY^_ss^}4H?jK)p`@Ys8HdnYj'
    b'`M#r!1p4o&8MWt_*(`AzF*=z=+GaE|anURnGi)(GzGcxghQ+|X<PUt><%u4)heS)q0gPF~SK<Z?6JU%hOd0{5>FRJ$cZE{&a8~W)'
    b'Z}T_5tuUbh{<&a0?ySP$TGeLea8(=4+?TtBUBLN#v(t;47a=?MRcpI38ld9jt00j(`9QbHW`9)rdK+~GBhmglhP`JD6Bl8PADtXt'
    b'r<~_JtBp)*ld{mw`DGh$ST{FRaK4rXxYekNjpYZJjjCuWZCAJcSz467LHRCIqm<Nnm3W`^o|{X_S3qB-NTyUnO2l8_q9LFvQ@~UU'
    b'2mm{(72Mb&#R9K(`W-5aT1qQV!B)8*PUDeKtDNY0L%ot7!OsUT$aq+-?6o@3oXL2!t49iwF}6z#T(5Oo2=<geuQ_W9=Tme$lxY;1'
    b's8}z4(Il8s_2erZA96JWE+~37>|(QOyrSHusYId1onrGfXe1c2Dcd=0k9L~7Gu{Y#nnq>UEpBFT?+AD*TcG>e>6VbD>C58omUrK#'
    b'5rI4^t?TJ^6|ig>hLm@}HIFWS*8|n39xFB9zIeF?^z%y&z*K;grih>^5~)BNO@GLC=r9KxDu6*th|cxQkkjB1|4+Zet*)y1ZexGR'
    b'^Di&l@|V7-jp4%YpyregV~gwZjdSMi{q<Z1{thT77`W>WuKxT{Zvirj-_VL&*TTYZ#Do+bCYa8ngre`{-JL2lQhBk3m-AT}?uB#8'
    b'!M8+xDRl9_3H;^v0NnEU5K9icAwfUzNMhbcXMyDpsPurKKO*g9*m*hiZ{~{x?-x>>B`(?%rA=5;Lh9hyTS7savV?<yklO@)6NQaH'
    b'zlNVWAl7`2<Uxu3c{q<Y2sK&81Ul2Gbb=^YRtYz_C6vYH`YQw*(JDCa5wH|_#J)dtP7s*^;W?v<jmZ|iGiR{ixcC9<+(Ey~DG<uP'
    b';k(tMLwAcxn=1r&Nnu?SESF~;3JMtr5f6<5D-@D2Q2|+apuw<WYjD-G+y~)@etCNQ>)W#n{F79&=daJ6*MLOsZRv!BDZ_YBGt&LC'
    b'_@MQ6$CTL`7p9HwDkU2AKx$@h>tn*VtUd{)GCG65q-YGNfq>GmWz_Ry&)wcAKwg(NA-ViMwp@%<ns9~8C$T-ds9I0*o5C;4O6BXe'
    b'x))8aHS17DYxb|WZ5+ox+qP$IfOmF4eQM)2LVfF?Ds*D|t>lxCJDEb@yptK3@5tZ%d^wG7SR<0>x6BV^)0^8BzxxoEAps4@lR!EN'
    b'zx3c$2t}@F+uYDJpGc;Mf|eVP9DCwonse+JzUwf=W-$ZTcOyMCEjAvHBBr&^RT3GZE@s{`+c)g78(3^IVv!jeY%+2D&@m>Moiz?Z'
    b'Q`ai<GP~OUvqs3}_+j`N^)HZb|2(+os5ry>;4}V-#Cp#7LL>*T7a>YjwDaH<RMzG<bwSzt03O-8WvuKvBkfSZRuEHaZgV3pPJcU0'
    b'nZ|B758HqP(cd0AqCEk<J3c>od&!fpT4jr7$vBenHDk7kbCq58x9X)$SV5c4visx)FK_jd<bwqo#`<ORVkjQud_~i*b=ho<g0)S{'
    b'u+HY>aiiXHsHvi<Hhst=e`Mj)ZI>r)oaFQ_ZPzte&R7;Xb_D(=T*}fvb9GOkf;0&D8&iAQ@XYIWF=T?^_)W*(l^kBnZkNNWBG6F+'
    b'Z$4+YS{^l|vnr{&Rq{qF9J50;2e)Q2U)y3l7LV{I6l*oG3@;qDTI2O}o(E>EqUO$jca(Jcd`fHnw_Mh0Df?7jdMscW*Gx_dKBA{f'
    b'1Z^bV9qMi(biH&2cDN1U-R$loQR4J>#=fmgWz8BUMRe69g?js;6j8#Kp4kPIb6bqd!~coNqK`<L%(gUF7<cEK*}C@nl@+viUz>LQ'
    b'6c=nuxm87q*~5<}$L%Sryl$<6nl}}FsSIn*TT)qYGcO$L36GPPrW|6bDX4`0980+f_OiDOQ}wb?%`cV7i}074Gn!8stw}Of@<?-O'
    b'q%s0HjZfQmI%yr}``?vMx~EjqAD%>-RAiA>Zb4((=>KQ3Mw@aCzfsO;UUS(Z@V++KzE&cX!tLAG4?V@Ykxt8^!IO{m-$S1pN>!G;'
    b'hH7@FxabNvwslhDMXXUN^Se?JS0vb8yR;e68oziJeyeRRk+;^Rw<!V9thzQNiDs_+EptTWi@T<XiVRWSiq`Azb{01p6E!)56*K8='
    b'q3u_`l4euXBvU|>KZ{HXMW5I%O#-tdFi9ep0)Y+hJOANXUBbgo`40O}cTgn2H%oRX4zEeWZAXZ`{<u2NoR~^p&#j1Wl#w^yG~xFR'
    b'MgCJ2z1SSQSO~!Rd6~CZ%He&=w*QP*nLjV{PQR86>Uyt1ky%V+Q%K~`+Xh4y24A?B;vSxUg+r^jY9$EH-D4xiRdJAe34_cTHp2eE'
    b'$I$$c!H+x(;#-A1J|^n%kwK4HOyW`DK!Ec5ldTI<-!9ToX|yrS@e5z)LVROgc%#TfsSIq~F|M&8tg$tpZHj4ZQKLLh=s#c8?m|u3'
    b'@fx3jtjMUOpd~T~ZOLYSz-Ht@^%Dix5C2oeS*s3>NFk&A5eY@oE_JLiW$dUfVXQ@>*wImC&e73PrQ5zS>F6kfxj5WU#u2nA@{MvC'
    b'GC%WVqZT%KfnooMB%OvZiF}HV<|Ea9&Am}4xN4GfT9`{hN)1+v0mc8N1v}g2=Lj*@n4nXepHoRvsGcf$EfoS1pHT0ZitXjHX$p_#'
    b'8r_&HBU4O{ni6I5c``?BvSf1EG0m*4RW3}L3ZrJih!B@wFdmfRTtcBpV+vz!jLUy=gYu58ZWmF?6>s4cP<Fexd=zcl=Zvlxc`MHq'
    b'J_n4Kp2rB&s$IlWE6iGWQv8)YTa&bfZ~1E&+_Hls@B9%b@t>g2BETx@<hW3O>KL7$QNaB+|80KpFkjs=4AA6s(t)}87~`g8T%YU4'
    b'oNxDQcx)m0^ymomQ-3u;?*_2&0mB<$F@3G#C48P@j&pC_*PMd1Eus#&{7M8eC8ici@`|1mX(ssZqvushgUuFI2BnI4!d{UUXaaJ5'
    b'^Ma@#bonzP7K%6LQK+jIGhlug{e-3w7Apri4AK$-vN66Tp5ClET5wVDwpIL9{;3X_O5~zjqk#$YBok0<@mcYq($U1`$yzb;I5i3m'
    b'T1?}hR%Fpz%6X^4x7`g|KMr+>k9ru_?x8B(zoMbzm)$A~WHl7{v-XcKe28DcViu$9@7|V3!EV`7?YWTemvlCHks}CajW^oBoV-uB'
    b'(-p&oz_JTits61$7juM|MqdKL?o(ZckYc8a1T>xBGW7ODN2zeWJp1#>TM*CDVgMU606F)`U*a9kudnKVyEuV)Tvq&2rJiW7E-&9*'
    b'c<;{7{`Plx<#x5YPYw?b@~=u>haI0@qLccU(_i5~@84oKhWPsU;?M7nFD}}4d~xy0JAQxp%DXsw@#m^}ygGYxQaSgkJd)CLUmt%k'
    b'#Wwd^9LU_uS6#gyXkZ`Eea0feD7gn1*PXvYHxBTQ-{$ly=B02q8@`|cp(*FONqb94rT2)_Upmo}70{s$fqqwgQ@JD{=GQ0wc$9lI'
    b'J^%Gh^OuK|N0S{w`Vx=eV1{9p^w)GA&ejo2=mR3f4KPuKKZJM^@>KQ>z0c$0l@W63M?<8(uJr5rF)5E3hu3|nU%I7sD`vxG*kA<j'
    b'U1`)1AMawY@^2FPHxFQ@p9d&c>HCP?gAr@UXF#u7FB3KZeGQcM^^9gNk0GzlFogaNX47Et04A$#4#NBO0Z{Gy=3zP?Ocy+@tKUAz'
    b'ws5<j>dd6Sl6vRQKo6MRv*i(O(-OtQhj*|9M`Cb8vW;Gmu8@8gFEDlFobjy2<S0gm9{hN}T&x!1Vm74Ik|UC{>en<|@uNTc<Uio`'
    b'Nj`ju#@J7l4kfn?&%+(6hkQFfe4-82;1}(>IW$Lkxd-+ThTy=cUV{lHnGfeRmnY|MPTzuV2u$+LyURQie0z5B_lwJuH~DXWeSP-)'
    b'_;rCV_BqQFpT0I#<|y(!WvD}1id<ks`5<SHUsX=wy07WlHVqVK3k?{%G$0lRUO$M~$AkHLHf!AsZAsfV1;fdagSw3QBjEF#CVmD`'
    b'9xT=?ikbjAK}uaGxAY(E^RTpC{Ox{OB_?HI5yu1xu$ta6XciUA^&I6t#*hn@l0v|}aJEQ5V?cR@4}wy=d}wy>h_=z!##_(0YB3d#'
    b'auE}dO$HY=il0Ng!Ck<L@XExKVcN>`vM-VG&fD9`EAh=mv6yyFuI_e$*IuJ;BUg>O<u}Xe8a(?C>4w`TKp}_~&hK4>`w)Iieaz`?'
    b'aUw2?SyV+uvf<_nm^{64mqrR=C9st$7EM@@M>&&{EPC!B?WyF1jq=&&9v5bRg{MV%Sq!D(^<L)0mS#MRSn&e@2ji|<`D@wlhPyzj'
    b'`UYQUOWU?K@EG2e+fiZImnd=<6S=~jC|0V)t)?8@k^G~-`+3Ioe2hxntTeZAL(<VbK(ad!#2}qo8^BZB^MJN|Kv%cEh67|u8JuUX'
    b'TX{lD=3p{Fy?NJ!aAhnhc7&Kl6$ALd9%{5ct)Kg@q>K*1;$5O{p3??7ImxdoRM@J=KneVe+WmSt8z#vuyioA3!GFP?_M=4%Pl;&{'
    b'd1VawaT*VKLjNIpY2=SmZAC98zyE;k!}{(+d<u8JT2hv&9~SBe{`vNjD|aUh<c&T5Oo13#bi}sQE@Fi`*@hw-4JV^M`as1ZM%s6i'
    b'eI;)k_lfY5bMn$FVBQUb&Up^I7d-GQd6a|%JK)JP+eq4Zj}DN5>J~;dztZ!&50Zdi`&vx0t_9uf>ila%0UV`)FLFohp^y(9zUF(`'
    b'dh!QWcoCm9c^IEOfz|&NO_Q<ZoxVJIdwF_!dU8RjnHMr@@pvA+;F2{Nswkf1Vw2H^#0i1MT*r%8IP*CtB&f{#h9u0oXHGnR4Uu>t'
    b'5z-`Bj>&=!2+wd4wTl<%sc#UNr)WryOGE^wF?-T?n0&$rfJjl>uq&b2@m*=`DUB+Z;eMi9Y$a<`=I>@JLZ(J@)7k6ld!SC@*7;z)'
    b'O#iiJqQB;r=8Ji-Sj?CYOpSZKXnfr5F0)0On~>8JGr@pIYD2E$%^ED^RMBm2i*OQ@=?RWQ3qPGjA-2S0Wf#k&Wt%8wFzghgjbyZw'
    b'Cvbkqj6=K=FIi(4Ukn5q_~C~QqohD9ic^)F3bXd6Ks<|2bI}9uvAH2x)KirBO$6-RM~dW}M>t!Yx>5|V<!QO`v9O4UpY;-8Vs|VN'
    b'fnNj=BEwGUFs<jZyar`b^BZ$$`5rXmbBbdd<_j0981K|7+RHP-flpBm5||RO|FCdgH*`VKYazonW=c{tFqDu{z=a5{NY?jwtE~{L'
    b'h``&}KH&ls<8;&TToF}<TRbNM$wGMV5!mI<zY$&FMZZ|~&v<`IHwFoDI1q3^#WAd~n2(>Zr1TciCEd@5OGHV8*<w;ZXU0_Ql07Vt'
    b'ePZOo{T=V6rf-p;o_NWJ>Al>N4|AkOo>?G;HrKTZZJ?C^TFvK>hcAc)RnDGdn5?3I`I0>DDueU_U#bD|6pmkRTu79DsXg%`Xqzcx'
    b'zFQ|;C}Gj}C8}?{j{t<rth^ilX3K@QxWgN5qzzbMg`seeURoyP?b78#QQ7`HWV4j}=GwfSMp$?bsE4fx7m}|rU;JbZXAl@dG)?>)'
    b'&|1-ZRo#qylGLn3O34VwRmjKr!jtTnKSNExA2816C`|q3l*z_mZDtJbKvyKJz3Kh!VxG1GM#tig!ojJQiRh)FJ**$SWdB-Ek&bQ`'
    b'bVqjQhk_dLp2Q1)T0_p=@qnxvS`$E9=p7M`4wxyvD3_dDKuC|QX_j<Kf;BLIY-NEVt0JmYz+|Myg%_mYKn=-ialf(E(7&g!`VWl3'
    b'nMqb~2$tRqxi2;~o8A#aN7VwBE+U+|`WCrNKva|Y`riBG^I6L~Mq(#C;Pu0FHfvrt;?Lq7q=_Mt<B1U^ehkb5Ucim=R*Mg8p0sE+'
    b'g);;`HT7{<(4Hagu$c4I5NsGop`kJVE&xMzu});OiD1Kc)Wo<`@~>_J`R|;@5rI6x7UT#qQaasEmcSk%3&7~b#<M^%ZYlK&8IN_f'
    b'FwTcggovn<zY$k#q`Zu2AXo-a$wOY_sCg~RA>`n<cyMsrC{9qUYd(NzsGz<iV6)Rn#KDvQFz+|Osel5_d2UkM81EFL(M70`IDqUk'
    b'eh&mmX*e{df3E3yfvKM{ovLOzC&A(QD}*swWy8z}6^sx?uTj>ks>Sr8ekquGe!2)Q0wQ?|>oL7s&&a}o|KBVZaLClgMKse3t{z;%'
    b'h)6lY+2qcrw36zPe@l_^t(wm-AgMgG;8eVt2`!1&DWym+{z$QXC95H?&)JTk51GE?-Ou3ssa2v)J!=vegzGf4OKzt{?7?;-HA%w?'
    b'l~|M@Iiq4udaa;NQW`fkJZGPz#!$+z6&~L^;S%S2-oDv_xg(5oDG}0)3DnX&LHg6hyrE@mv|tBj?u}@<AT2@R-b$(2hE_?u*mlN{'
    b'f(3a1h5D>+TPD8}AV&W#X(9&@g0@pEfB^$t-`_0#h&y3`K>a&$q%Z~=xfI7HZn<Y9tZCe6c}N-&oi<HctiIuJ6F0>|^lYH4k1W;G'
    b'v&pMmxTaO|N)=9RRyGkkLgZEg#w7Yznuk+B^0&p9B^%0kewG5B%h+3dl0u**DdhPM!FkC;kxK*2&8=xY(8VFxcSZnNp5amyM9G<G'
    b'@U5%>Ro5;sLDbPBCGAL>NP>o|tiKjZn<B1f(isUZ?Jt8|C(8+JCW*bCaPaljCfY5Mha?PYnFGD1_BD_3;%6B-Qi~0&>Vlxb$S$F)'
    b'0Sx;0)6$*te%j+VOD(q2!^?7YUAgu{&JfzT3eskC;CZ2Ne%w-Q#tYGLN!!hxn>2b@`afi5L$DV1H|ZaFjfz{I8~RCslqG_)FlkHf'
    b'f+D(pI+T2_1$9Xg$lQc~&N;NIFWpPbKCbDd^@4=J1%@e*@dOEgo^p=@gf+IEl6scO!2zJ@P{7e$EpmJe^FGppTifc^#mt-MziU<5'
    b'##Z-J_ph;w$5wc1UX{lbd1!3;u_)o#cqPK*@Ufte8(Q86;M0aK_5iE0X?gaNWWTAC$0X3UTcVw_$guh9?2X~x0_HdMv7e~wO}#uW'
    b'9BWhSdx_TB)X6>q0yb{=qwZw2o_epxZwm#a3Bt5Qfj_b*p>DXQV@yV|=|uKqY}w{WA4fLRt#}fSVrJ-}J+=)uu=U9#h<tnOT9Fx!'
    b'ZS4vC53i4<1q+=>Gi$a0Nksrq{7&=f)2HVQ5$`*6{<31@D91YSa&gx|?ENK9Kk2M)!S=to?chRnq@3<>(`5)vQInKubky;a)sVoJ'
    b'yGnUeZM}*IV_E-zvJDZ?0v=G(578xv$TUj1ffxxJQ69fONfEqf30`6oN`A129&%|ki1R*8$UBSmgW%ad4d?|XV!dQ>@334+6C0h2'
    b'ST1;>&}enTbE>-8#ioB*&&dS?t@FN)lZSbzeA}z)l$y=TKw-aW{ckLqfgR8{#et+R(TL`q%8TN<4wcv8Ra)Gt3VSc*Da^=%@3j&U'
    b'ln;lSE)&Ec0TZ};MMK9OoiDDjL`Wn)&_Yv|J3Wz-7sbe57xUs_Xjif~1gHo!kta&Da>aWbbd1Bf05tMMm%Sp*JrPsKe0*xRhtQp4'
    b'3!^+R;5qvaKUJ=$nqOC1tv52ZEIoDE5fS(|g=G_gX4J7bvLdCkbaIs=E6+mX>6VifaSAA-XVYNF;XewnO?={649)PCeU7F#7|21('
    b'QOB#A7UP8g5lB}+SrtJ;5)+72_sRv~X_Ie#6k;z-KNcp>!_Kha=r#pnTjEi}zfmKHHpG`NrGLH)@*J8u(l~!-(O^zvFzi7os5**X'
    b'@N0)|+W1ghMD&VyLhnGeR35`)T>u8cdtB&9sY~$o`115GCmaE@n2wIJlmwUp3M5*ndvYkCaPB^UWE3%^oYD4qpq;lUmU$_*pknTb'
    b'L84!q6ogo}Q-T#E0rvRf{W-ySa_Uh=S->(ZWh~;PvS=vs|A1D@b147c_P+hOZ6jItcmEYAZ`Gl=CS`yGUvjbPD6!(W;#XPDIh)ez'
    b'vOof`S&>OyQL^LX>;L^u_dGCf3`ojRa<sKcL=yABJbJo&y1y?HPH!{oHDuL`;%6;7yX<<ph3InJuru+Z<=vsjvR6A&7_myYi+1C0'
    b'z)n#X2|ir!UcY{E3LHWbzBgZyGumgw^tPitd2mP^;-%do(olb=Rq;7V!R|>0Tz~GT{I6s}EqzuUdMXt|KNJ$5t#T>I3<&bbmY>Ag'
    b'ph%KzG@dN7alV*LiupLtvZA+0iZM}!MsXZ~YA)B$pz-JPewrk`ey=~wdgHh^niq@3U{J)vvOieNdy{lNA0^|`4vqh{1%#?^XpF=O'
    b'v1FfbHaEqq?9=i+-6a(AV4s-qe&~5O<UJhV@4@W3T4x`@8A0amD!bkmLI3u!`QH=s4$Q?Oy8^GD=r%dVK{u_%<|iutoEUCoWqyP!'
    b'_v*G)>D5*=Apv0h{2CwTh+B_~<qV=}zUcG-wr%WhLVdov@MG)7(v|Qg!bl#JMJT+zRPj&=6u$Wr%Pa?581}ye)1?(o(uT!;d-3}C'
    b'X;nOFH|esDM*_I&FDb{J1QpL;=$ohRGpTQ8tpP~z9)?<}v<FKC5bKixAj*?rn4H&3QnmnPcX@@MDGqu8eqm({rsrHhh3rr>tF7&('
    b'e)N;$O+L7NAoq*@VA$*R(yTw~<!RbW`)QH)#`DE^m}EuSAH|C@85iWo;iM!d)O<3U$Jux|AZ14Lau9GFp(AUVGa%+x+=KHhE_(5#'
    b'm!)xUFe(=1xR_+*$m^Gb(P)?w(|^!cARU-Dk8>0<9Nqi?LA#6*<6L60k`;*K8MVZGM5qP9jix=bI$$nE$9*IpdhgF#7<7P0{+2K6'
    b'2V7jc=<?HSs}rf}YFqlk#cm9@XQW2BslNR1WrMz35wQrKD+(&e1AF=X2GMVv2&4wDp>1qg+4^^=5pS$96@%X@EbaD6AmO0Vc<648'
    b'Ec>R8o?Cm1w<phE9utXo#`}EUT!^rjJ8PuVod*k^yk8c1RxTz*Sxk~quNRl;V$fU6)5W-#kJ4T_PUCFUk4J-am}mV#k>**_C$cBb'
    b'M`b>5HP{DE;s<r%bRucJO{;ZM%b8Q(5L=lI`mDiwZf>*NzP3cqHA`td`!o=4dLC&jU$$_q=_30=!{KRQwLJmV%5W_Mkaq;+VwYIP'
    b'2LCk^wD2eEOP8j8Il$`y`L4R{K(D;uP~^DvK*`JlOG0t$J%=}{DKHi?mc3?-2SC{8#YI?gADBD#<BShg2$Z`#_@cbwIcS8f@2td%'
    b'x9@s75QE>>UI;3`vZ~y5?F!c~txM5}j5T*&9g&jzz*C{LwABjns|qMTjYCKTSOplGQK+wtbOMZ9-85Td@RbVgpH(NtZ%Ht|P_5sH'
    b'boQQt_=ot#Ob~y?<FyAs|ER^r!2|3c?FHH2(Dpc#yrCcIq~z>U8(oe(5`qSb$e|~CoEN_wCj)y~*n~Pt8!FXR;u>&BNqEhjNX6^!'
    b'D2UC9L>94STy*V6E(1orTPoZ4xh|{mZB>#9c$qe`S}>GGv0#U(x!v>%7z3%TxNW!6(bhRXq>?tWkE)Qw)lro>`^qMY{Lm8f0v{;a'
    b'c<bA_oyDW7!Z=rIU?~H35+fZ`sR>(b{|LW1-`ZPmERPKmxU*<LpXxo*b3bWz1SHn5YX)>OV{ksqqsUU&f((dzs^Ql8>*Z0!*sMCy'
    b'D=&`67W(Elg+x<!TS((_uwC0YwLpR69ko`)X9{scz6CTe7$B4iB8bSAy^LW@<Vj8!0e>Hu5Doa-%?jE&u!0p=$05hKX7$mJv+K3z'
    b'?&pCY(3`*6k;(J`BW&fXu$<FkQ0&kZM&0z^XQT-@!T(Q`oCC`ad`ylUkjU%J;SI#g98iMy)n<CY2lx=21Mu5ywdq9iw;$QJ?YcLR'
    b'X3{nkdvFfeOyW8U2eI1a6W<gniXZ8x<wfyoef<;M;!;85#}jGxQcgr|95Z5Uu|-LCH*9YB5-&VqXV$EA+X9qaal7|c(7ajI#J1Tp'
    b'2NHX;;ohO+n&m65y=IH6i<10{h1lt#fjq&N29Q-58PwQlK*A#~%BPModr~K0IWdfjEC+?JAb>fL>0MCpbU^-GA<|Cd_>ujDqU!PE'
    b'h%?Ci+fdPr^<^Ve3D@JE?5@07SSOw41M948B|I@XCadDyiD!FBKN#s<RCjFqVYw1(8v-3sFH~yzm|Y69qAbXdQp_(6CjVakV85pc'
    b'{@~~YPP2ktKQJF#fWJoO2XRQeI=4+#%bCNYKx4)JXjznTQL^@4{XBX!rFupKyLWGFbb;<oLDiuPWwz;gCM?e+;&;<<`#?RB%<@#i'
    b'I9L*ZV=+>&dpUB^gUercYRSXnGU2UY`=Wj86^+*0!<$Q}@PJh)xsaxwAQbs&1n6@Gl(<~Wx(h<9;MMWV6GN5Q<I8JK2lM68h|peA'
    b'`cCv)-~a4vG&sj-@5l*2ACQb~^t-hh8NT~*|0u&pyVY#zR5y)hh?@rgrHM3#fA{+?@oL9I_&g)sVc~IbFm)Jxm7-OBw(y04iKDX|'
    b'dpW}(K$*EVD>gSPMHM4EwA|^|t0m`3w+|7dE<Z534(67FtBWfe2bvz}j69V8SG^-wH&si2O}CZ0qn|!Me)j71>AUAYQt9x+i`PG#'
    b'itBeX!twLQa+wUNm<X7_^0h<`%!X&%%2_ZFR0u#s83wNgaLGkBEK{<0AYzKE+{%*D&mSA{S)J}CKma2Lxf|<18^_(s@aE;FrlE~&'
    b'Q6a}$tsaEF6ow7j5^tpi6bXK|RbKpo^9`#Lo8~<ZXJ=zXWpH<goNQ6+`U}mftL}juR<V${7~#R24yR>f6;N6>c$aWmH7?At7^?CG'
    b'NbG~wS=^mu-SYfv8h?YAV6NDXTA&kQCj2xBX_0cM87(TGbpkeMnv$-Ozk*u9Q4el~i5k)hXRh(J13D%fYj$s^RJ$Fw8(n@={I}|L'
    b'*=5Ty8;tL`#wV_wkZKQmu#$<QGESjJk2elE9QiqPV6x9z#5U++L}#lLIh8#a1VN5+q=k~}`kueN3fVXU0u>F~nBLo=>cmOibgPL!'
    b'LRM-<x73lw=mfo;)1Pqm1aPx)+o-)F5HT?*m58O$w%pA-tFrXRF;uSZS^6bXI3uu5!n<edmz2Io6N)i=&*X1XIQQs{Jh1K=nP1gp'
    b'1&)i(Xy=F?^>pN7!>*}~0U&2ZA$T?hN9S#`PnL`kg>R3G0Q0b?nq%$zB6S!S9gRl|N?Us8)lO>_PzSrV5`*O8uC3KF@ek1|x))34'
    b'N$$`ex77umbAxoZ`UrD2F9)-v)g#3agcz&@y>6q4w-WveOSMJx3%I6}oKol~Xh!KJpFRfcvo6%tV@&7siBvj9Arrr8Cz9ljupUU1'
    b'C{aItYA(VJos+k6X0xWxJqJv1z4i*NHK}T56~9HP2c!_O>L;jOM0R0fkNVv8hbq#{8!=YJAb_-%TELIIh0Cku`iiz8@`t1k$%KZL'
    b'U77ImcD~ifOSsCd7ei~%wuhIVAhjRk9kKAvk80I!5wfI^lU5Y*ZkLm9x}8csPPeNuJX@jr$}!w3W%a>&m+G)3s(36j@$=VJ_9<Il'
    b'KsI2+9;+Gc?UgiS#;r^hv97B#*cKWRKHbh<1kAs@C2AIdZT2-L*0AQ(m#<%OEEA3mQVkukOEua;Me-4S$Z>x}YPi*@T2^5H0>+rd'
    b'9l4P8+9jE(%>vzH&6tsm7z+`@WZ&eFg4CfAhfd>^)Q5K!vU=BMgus=cwz2n;(?u5F4#ME-DU|De0@=#Qvaq?BYmdFZy6Ne`QB@SZ'
    b'jBtoq{<&*>w`7cNuI=os;cV>$-%j(<;~-VoB{UN__7a3tur%Kp0ENup{R)N?rP=F&*ZP#Fq`I|lv9^%H&qiy<uOH>11U|K=&)-fr'
    b'*H;I$!Z!W#`KzZV|C;^u{KX0WrniBvm6n#_BB(N~w3=kvk;3l9yOXy>&YkE_JU=;wa7CG)4!mzbei0#GbCvvXGiRX9hhzdd2V~S*'
    b'GT8BM7l?iEum1~6ta>-1Ad>p0QX6D*!&=nR_{IC;V76Jj!8MUt2Q9`AgKB|PHI-V@`3(z${C4n9WU7pSx>@I)mMxU(ohT3>r5h73'
    b'hqau8XN!D0h02Uq5g;DzL(;FMeA5E`Xn_-7Xqw$Fg7&p`z*JZ-;YJ&)hA4+F<B5XGKhq{QWMn{>!gsH^RZyzNO6eVBmo7D|FUxcK'
    b'2j&_tSLK>HGpSpXbf{wqnPY2~_mwhf;y6^#{3CitWHH$vWE*Z!A44lJNh7+OBl07F$7B&=yhYb*xbFg_qawQgP(;AYfPNUMMj!(O'
    b'DwB(7ReX+qJ~@7R7*$RiD8YtI^pG@?MO;oqK#g$dG$4(wtS;({BD<oCx+blx@vQ*$c(5+>+Y#*=pz&HV7AUJfXj$m1fx5PvU21h4'
    b'v6kW@!M%0@LjP(GG}qMa=REUIB){XO^C*C1tR6upmdt-ruMx%X5XYiI)(4`m!>k-#4jSH3ECL%y)~?WpW;jS0E(<)|T9l)CzZjKq'
    b'Ia>6Rcrfqv7ioV|_WDVh50hbkJRUBR-mul?c3j1F*Y8gdZ6^a^)vC^R&H=xLCtb0Tik4M{s|wOG>?m`YSBhPwaMhd6T54||<KkJa'
    b'SJdV-nMIkJzo!@U@Cn{X)-H~=K`bc04<C20t4_rdgi2K;!99B6SW|wz*2b&lqt)hKR!W8CiaVolDjw!5E2BJ)217ms9tNR)BD@|0'
    b'<>MfTR%Smz4UQNtDvx~Bl30Z)&Y;QX9s!}d#tUy0bU4f?WxJyple69OpvDTXKk;oJt3pung{%s-Jn&FPIuT_=ztpKHy{AVQgL~Lg'
    b'3nAT$OeXgT*AH1HyO6m@l_t;W+@p%mJyHnWBbCuTswmx!8`Ff0XdMf?#@`+p*59yMCGj~WbdLn1dn8l3M=nnHNG5fU+^p{YY<_Jg'
    b'ZNmT`wLp9ni}4^H4YN^}7QJ*>OwwX9&hv7dl*9R`U*tuv)G6T0i|oCd0Y1_x;3FFceB>p8j~p!UQ4I~eOAmg&I)F~IMa(C#?J%Kt'
    b'<A#qoIef&};hCUga?Rj}kL(2Tk&PifQYqr20FHPM!Fgn5I5+v_b+Nk(zdWO5kG5cRw^P$c+i}wiYI(IM>N(4_4T?@IXw4ANxdPQy'
    b'p>wZ_k{rnOtn5BI-N-_d8z}_15i;N+1CGpiYsa%vX>cQx2lo&0lgfe{?S%&S`y9JE8Eym};0_xHA8xc0w|lr^7j)t#s*Gh+^teXO'
    b'4ics@kkiJlQq(`tOS#r@v}Ks$J~boudUtm^z-PicX%!19gtY~>8}A?$@=<2Lp(LrvhL`Du$sh{jxYca-u*QzK+6>!_I4SHyV^iq6'
    b'%_8fdl|$HTO35QGxYYfj!0;%WJbY5I#?kd5E)6@Xsm`1sj_V<>j;EUZjW4gs6Sl}%1datiPhI>#xJSTuTgM03ceND&A+386EZ%iC'
    b'Qud79#_|n@=r%0Ats+XBY!U9<d&3}zp9<uZAhc+eamK*K6?{_w20yEy%AqqT^9<^$j3JQE3d$9Cs~Eo=3fv3pE9r{wnZmz<TOU*%'
    b'aI4e5I1;>2abZ2Tr0HwHBlu&bU_4Nr${4&Sr^B)~JG^lzPgbrOmP_^dUwDCy|2(kn8%zE37CLRkTm#AM!9#?KDDsDGvM%9ni$C3@'
    b'X0zuk!#DZ|PbI`Jn)jF$^0mrw4jOhoJVp83k@3vt)1~#g)6T&;n*G5O&fQCsr~ldl6%j_fB44d2?2)1j8G2~uqBrx!1t=%b%IzSg'
    b'Z(hHBcl^VP69vU|3kXtCkBVwd-mOd)*?d%#lU`OX$p7<sUZhEq=fx<Qr`a$bjC&!d)@lnZnrAc^3@3S74D)f34;H<CQB20eK{8CU'
    b'aULg&UeQm7Niy`+PveXARybVl!8Sm~-wVySIWTj(Nj5YE4}(xMJxG!wmC@@W_(aUHF2z|31Z1+TyN1csEwQpI{IE@{Q8IM{{5xqV'
    b'qzbHEICny}nbBdjh<z-+s<uS~l8tBMK%^9)xBt507|kq9s9gg?$0k>5TjYfT$Q@&HrPyze0PBvW&bxEa?dZLHPA!<dx0QZgBNH7t'
    b'<`rusO;eN^8mZq1xmVFj1llEX3S2K43j)M*EX?R2EjL#5%O{`R@CG<kAxs~<o$mDq(%CLTxUMg{)YKDD^4evD#Ofg)G4lp3K?ABt'
    b'H77-62x%AmPuMS8vUpTgD`+FZ{2aIYYE(03{gc~$5^b)tkC)Yt4!A1ItNGEKo>b6Hv@8X0!q!yeCh?UAwrQKx@4)44k6CB$>x3=('
    b'vpTdL`q!U5d{1oaN3oxRGpR8}yE@}4HSOf5*Kb)Cke;vp_3}uM?okKtv4&A+g4C&7@7sf*#40VTiB{U-=}h=0{2V%O;EAi;435lG'
    b'Ol^9!eV(_NdNmY?-fhYmrAiuYyWO#6c2`;5X?Q9(%iv}S-Szp~^DLj@@s6+Vi|C(DD+P~~q8ZyYS<O%eGp9*`v*r1e{>My|=D}q3'
    b')zQ>%R-H)r&bnpXov?)OR^0k$8h7Y3oth+XqV~YcFeQwZ@#I2pzqClzY-M%!lFq#4QqwJ4us3E3&u_&mTbaESIE`lL0bU?isfaqp'
    b'Vbn}G9s!2d$nbIbq-xZF2P#CYE_@h8+}qdxEn)39hT0F|6+;$)P;mWtJQ@xs@o+SmWc`>}$VJvm=7V8BAI76zS(f9Z7^MCAJW2C>'
    b'F`V?r*<?N_;<P{LP5Q%8>sC2OdPR|zah@%P{kRxTMtKtF@o+F1WJ$K@4MzDO&eKUbDay2$6y>Ch7s()<6oZl&_GLV7`GD)V4@va`'
    b'VcIN(xTWR`1+qOCuD!}b^}y-C{><}leHFEXoJh8V-ar33fSe$yq&m5@Xdf820boShqt=6$9><mh^U%3<=;6+LMw_h*(t3j##jUFQ'
    b'c-@;d1Vq}CCH26}#M}*l!Q&l!B;hZpvtfF=LZdh>_zOy=8ae1PIK+<BfZa!}Iehy_x^;Tw?YRuAz=zriU?4Z|sa5Zjb1-b(G(9Vi'
    b'G>iqZvdtbUc~@j`Fyjw%u9|jQPuLR=zc~Kw<gLX&({^^E0T6=OH-{mLs_nE+MGt&wrw$LBV>iv+3JjpC@sH+@K!1NEw0A>wr}|KX'
    b'(Ua2}8qK~HQ(>yv9gnV5FbCTGD;36J52#`FxDJne3*hYXTp8FvfQL|EhetM82MgP6+nvpBMdK|#Q#JCE@AM>{C4*U?{CmQ(^D4%2'
    b'#(RHZlF)=|;YOH@l=J9`@l`V(sStJnI!ql3xizh^&X4W^USKy(M1gCacW9TImZc;j9eR8O7Zz`%LO*ym+HN2f0T>l_WC;!|0oPb8'
    b'uStWBP%cFTMnp?mj9@Ig@E$lbuCl;Qp+ZeQb+u`mq9)~kI@PrVHsSu<esUP`q<*$xu`7C(z4h)d5E#Vb44~)^)&^O4jI02(O0K$C'
    b'K^-)O2?nCEdM1*vN$<o;II2(={#k>$AT)~rEP;mSjnkLHE{+WKgpOzPlz&pQd?6*z&Lf)aZ@pv+sFr8?+b10J{ArrMJImiPd=@Yb'
    b'X%^-Ec@&tIUv*WkiKXOA8Tn!3AiwQao<{i~;uluUPoU0D`H9VsCN2Ammp5>m$+2EVUz&)`exznT_R|oU=3M}jgYl9Z;UWjP44me!'
    b'6;_vzhgVt9#=&+*`$SVmEg+AEC2+$u&!-N%337yFW9b&&Tno;%YA2nR`F`@3PUL9tgF8T@!6{4uqo;nj=pB~<X{XT=*e?L|9w*F_'
    b'+Dr`yZ)&rg$V>%>-O-?LTAQ1}@Gn%!v54VVr5{_fj~#lRMMsg9wW4wmS@VwJdCd9JRXh)((=Lg}*1Y2#Ud<U83_}{2TwH0vMrtua'
    b'|L>4g?6LhsO0m0e(}ZGnQq+XV*G0e^xx_dKOUNYV#LPT#nB@_ppLk#6B2q`{$EBmkSL@-`_?4DUyZZo!WQj;wvXECdwWr1s%@8vV'
    b'pU~_(&r|dPcNawBY47N~bGB91r+de@YufFdcZPBMiJDa@C$sXbO8pUEqNl5jEwR+d+BEv9q&K<}1|eVYiJ9c6<i2;5nzS7=2j?2@'
    b'7OsBMoVXdp!a&j=I-6(`5M_3{Sa0m4#v%*QoDU-W^z)`!@(-XYQPb16%ao)a*y5d_!@AK{qM|v=YtwP)IO2%R%_RVK{oF{6q~Ah1'
    b'B;2NpWJvn8ocd_;Onn#Wr6(rRcT^J*Z)eCuBv_&Y`XD+VOu#{cQniDbgYeg%F?e;NpZ53sjtpi`i;c>1Gh3`(3qZ;DtiPCSSk;uM'
    b'b%_Q09fgh=ptaE}ATkEG;=2gYp>Am*cu`uI`SG;aEUt*LLNsHFtW=wO_3+`t%21%L^T+5iiCF0ErW2ut8Wo@5*jW_Ox&%iO!k9si'
    b'AYFjeB91BrOHey{E&*?IeS>&u#2&f6zG9cytyx}mea5P2>EL|JvZ{fBrojV8;@d+2xLV!FcHlLSHHNU&fB<BvA6;TOe=1fy2zk@h'
    b'V^3_IX3b#jn!=FhKeFzLCwPb34{X8A)nnjmsD(g#dUE>X+vjhP$lG$+>WcWaJhWw8vn{4s?o@DGvoG#Y9&;P%p3<Ned)n?qV+-}q'
    b'`nvM|5#hBY?c{7>3hxQWG=n`i&lbOTqJMTG@SIHb$WvuYE!H0jiXle!?$u)m)gtw8B6{%`F;N+1t4QKAkHC>5HkA|^25C8m`OU{m'
    b'G!%KqmRM-o1Aq(^D%obST+;b5kO)j1%Aj1JwmTem35)a^<poiXh#{a_Y1Q|KCx0xjPp`?~9iY72T;n+YTXp4nQeWk%MJHTKnxHdz'
    b'>xygX_O|tlrBkt5dPC&c_=@gG*bj2>*&h1y_V~YR`=o`uwT*xcSh=PToh(f!y{O|o?Za+~25=0B8FLJ)f;<aR32f~g1dfr5j+DGs'
    b'yKRdx<D2<F+vfUhfRUJ-#N!!DGeWCNWF*s^8rUVwN?T+G<O0x@O(S{OMspgF%HrE33@jGOME1V?qPt})TcxX(9||wXdPBO47@YCg'
    b'Q-!-Ydj(QMO%qMyI-yW#TxWkYA7{NJE(XaWUc|%RWSEvkUgk+U>?i$V&>v3*<-9i-lxaE~<nw+}lyMnnM5oOslYT(dDGxPTBV%G~'
    b'l1%!eq8QC5!$~|J$9WN_qioSj=Vd%f$MbSBSPbIA8_&91b~^InHLBf_NUBxq9%lO*4XV`z14X;4L#CNZg}!6uMK)g|1b_(Vc3=ps'
    b'(Lf}-QDhL%y}c?v)B9*Ug24Xvr2|Dk+9yUDj9^+Jg8TK`=g+|71kXQzN`~wCyXPmTIy4!F9>B)Vc=>ZvKd@&wibx>-NApZa@9R0!'
    b'^Y7sk?kIf1-xMH0T9$fzyA>|`JrV!J5I8^_K3OJ=ewe*GIeo{qkt4?QF-#kB3Iyp3+jR}1B}K;?lO1?FW`sm038d4cOd84&ksxcO'
    b'KnkJ<R>-oUkP`CSsc;WO0T}ltqy9V{5#2XUdh-c6-Y0`%lI3wf9!<vCyjNs{fRo;6g!8w|Np1aJGD(VZ)E{P(Y&4G3{x}|!#?#So'
    b'F_`zVteCXI3|+&VhmD!klm%2sXZer{tc8Dj@%s3w=!8!X^tKPn%KEb$?AzXZ?P~v{|L1y63L<9X)o3ZW!s!92^`(;5>GRq6u9?oH'
    b'2{O<?q~GMAarGCStjC80CO3AB>KEmY`K>A~KO>RL=&isIq=4d2{uy+lKKyrbUO&1{SC7b?v0BKaU%prpqcv+KRj7%rw(3{kYQ6c0'
    b'TM8eQU@2(c0e%ZBp{9BAHp4;vScxbWdC+PG%Bo0r>>aW}P87@cAFf48BeVD+at4@(_-($hoypliHC`h&4j<1e&%>53KATnG7bUFa'
    b'P|=}zU@5<)WBLNUB6{kZ$RL&2G@me!0q<^=&iTY<goLJzhHy&+q=W}1UCPX%^qH0=w71T<hH5(|32A%VZW=xWS~m;p+`gaG2~cy='
    b'Rr46oz#8y0w?hbVS=D4PnU6r-+7;p#kI`XhL}Vc&k`g)HKv~myN!<XWRxBqDaim~0QTV3Ooc&S8Df{cwfOBRdE)^%WWROqJq<<I4'
    b'lS9Te#Cfu8avydPe`6EpNs-#@z9|IzsT#Q5po|QRrO{leu^B>^Q5#I7ySf_USEII115af^mFQquc46&+%Cf~6d)i`TkRff+oF#w{'
    b'u<>Q8)#~V5_G)*>-jYDFf)6#`h&nS(Yk`of+XvjL*D)QKTS(2kE@$+TScBZ+u0}3E0YL&p<|g|Hh+EmULltsz^6g(+QnR!6d!@W1'
    b'h*XVM(xDkHEf~x$6t^M0GzOtEYS<?xmFav}-X2PCmj6TE%=lVVN=|>#5`A{hU|4%uM-8TrpQ-N2+Xtf7_kOENDYCtos>mO{M<c|A'
    b'#I-CXgJ2qXQEyMgqwO|EmQju#TVK4_97j!VI;EF}Qp*hs?O`J(&{O^qN%2b8*+s!7`roTohzwA!#Qx0XR0nc)yCE>@QFc*eB_2=N'
    b'YJp30w)ygLzJ}m?*npeaa)ohmfPHjxjekO2c-2i$Iy1^R;3)fUXO0OphVN5@9>;v!*UJ?$tVnFQhj{W(NEleKtU3%l^jhM!)lLf^'
    b'$xXReMIC0I1o<b`=Ued(VMcp3rT^IpJ$`RHW-F|~nt?V>nBdjnqfeFqkdz=R1Neh=DRkLkCEe^|nQcsA#~URpAEE`_^N%{cIkG#%'
    b'Niw0(g|Y0mT-r}i_@jLUY|)U8QEfC7;z9eq;p!NqCkbF#OWdQmo46olF_Sy)rhV)ri}AuOE^e&wSjCGkGadygu<mA;0O<TNdtcc6'
    b'JGD|=@}h=rqkXw?C^{a73c#O|=eDUqiV9ifmIXb?uDmg)td|v--<K-|%_3gGW^t*y!}m0Y>=V<AT9uXEt;XRAgO9=y#UkS_Jlf`n'
    b'5dp6=z~PyZB{ySN|M?VJ+3wuIA|i~JO)?MP4ckgAvKRZH?Hma+Qj~(B#xcaL!id`VwFj~!YznF^N$>3UlTr_K7Z7m3?MXjTgwu#l'
    b'8vl)c;6G9PKiP|#U#)@Ux5a$7SR~I|4UV(jHXp>&G~H=WIHn~jPHc6jTUHvSBdh0L_|k@{&mAZYuUe1T7y%x+YF3UMJ2Rjw(rg}C'
    b'cW6LI=o&au03jiu={&&YD<n`Q=h}53<?^HMTL`s1T$M)@5KK+nH=pGzmp#rL+Xo?9jkp&u7B8uaEN$_7CDfyq)i3&lHqJboqTDSy'
    b'DEBAFsKz28NEV1|LPmAN(i~`|3^2FqiUy$Vy2vsxw3T<cJc?{+d}QU+;_(@#;5R*aqZUXTfI+cZ1oL#@X=}<6SziL$1!Xz&?XrPm'
    b'Krna%PMyE>rW>YtgFBTT0oPwHO&4!4csUcD3|mW@G1I~nGq)wdq7NDzhjLqRaCvzmXtS;FGIDdIql7B~OO=6^7k^Y(;pCBEu<(eX'
    b'g-0!ZV!|w`SBP+WQj5j~Azqz`VL;-ZJ4Ae!8W3<=98tx^QHtfxrL&cOVFHau9BEvk`t%%z^z1R(u_KR*^Qfbh0AN}#47qYg26NEh'
    b'-Pmp?tw;2JE((3SYL=^M;I~yuV;=N$y`Uk2_?S>Jba?ofEhmiqb|bAT2Zyo|Iw-!T*fZv6W@pO3-2q&?Y<+&`#drT!inxi&wW~a6'
    b'j)MH~;lq<ZV9LoFfdL_#_8Iw86n_$})=`<wuW(W102go(2@Ez$_DN<>Nye)~R*w9^s4%7#zOn{)ZH+Ar#aNE&K$fYBNf+ml6CIU;'
    b'4?#EQGP$S3`dR;iDgqJ4{b~?I&JOx359qdUC|$2&1ruiPQ6V*t=HexAH96p#sid(0HaC4e7ld<2*lF9-w+1-QjxIaEoDG0oQ+;7+'
    b'v<=3j&Baio-l_qzJ5EFZ__I~@^b+j~Jw??`ZKG{NMHaC<`slEZdYD+-7PM9m;(QglPf?43LX74%LXMOg&X3nfL^CGe60<d5f6SIE'
    b'LkWhw%Z+N1szTjI5{!kb5EBXd%Ld2gs`Ei}HCe`nkg$~_542^ZVp|H~>jGG=Y%R-)NuexlM`n#DCKPE|bgxNK2DB^=i=eXdYpICH'
    b'b+RC&b_a@c6a?ek6v8<QfD<<A{3?ke3P6M((JPI6!*QN`^91aFt;>P&@}at+L_IRhf(a8@DaXavQkH;J>YEXQigJcuOi+${hHQlp'
    b'OoHnkO>Vr+pn(@(XgW4P-_E%5rb{0z1P*$Erd?55^3N4kG5-c;z02cH@q_l8T7@}k8a}tqS}H6P@eRl9M(-StgH6OA18XB}82b1a'
    b'`;bhq0mK7_da2_W-ldCHr5$V>hp8T+C-OmqR}PFCDeOQ8w`#bRobqFYvp7kL5+3<r!nfHn^#;GPARHZF7)hE^+A3wm+ln6U@Gcn5'
    b'Rk|Z2G2;Z|A3O(E0o;Zf0hR<lLJZo~^#+bdzEPr9d)pcF4|Kph$~(?KnGNMzJFMwjoy>h&lmY_0>N^WTu3+KK8-$=<w0=H0eyX>?'
    b'E<9M>WkB81c@_XWzm2Ny-yj$`y*K!IlMz{78+6jQ#h_PRR_^*?nOXWDp9eL-VeTUj&V59I?jtwSJzjOlhFu$E%-I1yynLb*xXk(4'
    b'=H95CdTUC#Oy{ShMNPpL<)hN7wKQ*0K5)GnPrLH`)S>&!bEIxPhVUOXhWK}T1h9c-UI4XEl~&=13bU@UFlV)&nZSAP*4Vfcz<)OP'
    b'>Q>g?wjn?JumV-hTD^hyaT{R1!u68a^756}aKK5%DF&vK>LB8akm!K7&2|t4(;c`rbN~%PCu+<*;A*WABSEx1CBZga&dQat4G3RM'
    b'Y^~oxn^K3-Kdn>3jdJpU*})iG18+@^p1QrNbsP_S94w9N!Q~+VL(VoH`VSTDgKIDxbP|!x&0$hUm;n`>JR+*tBOsc>%OAnTH9kJY'
    b'e{U}<YbOQhCYnu%NYXb5D4GsP#aw}ZxQQ$51B8X9`0qb`fGlJe+}G@-yLkBU;Y)f2N0I%z5d0C%sZ)AcY@+q*;>(lh`a`iP@UYrM'
    b'm&FyChL3Pbw<@kbudjZOkSReyoK-0_9@O0nnIhJ8DP&=4GOo6OytBI4vXg5x<7icE=b~j*6sv-?%zL_XU1qoKaH{IvifY5owXyS?'
    b'8jKs&NVA3jV3?7nQf)4fhr=2N&6zkV-fxAD12SG<k%DG~tB)b>-&|pQcr#WCm$s?$b@<9RW$X|Fp217|05ZJr(pKUQ7_FO4VPo!C'
    b'tyfC`@Fd^CNg@$>%wUXwtDr*JH#RO)ry0oGSCt{*NQw{Wl3sSR?xrA>;rf5}bNy2;)c{!=etiAvr{~Yee|~-S4k}5o*6N2}PJWxk'
    b'@I%E0@H1|luzLUN_{Fa$v;xmdkmpZNf5vTk{OTz@d?PG6Pdh)qd-n#|CjRvs@8Hqn$7Eh04*77oLg|lA9P-?0?StR^m}0WkBhA+~'
    b')|Lv+-vAz0p!G*OTz{nF^+)u}24pQw_D%>!e<XqQQz6o!M;Te-c48KH^|bsU<0a`x@*jUdaoW9DLk=qb$=E11^b_c`T{vplbEGLR'
    b'jFH@0?;L<&JrC2<+3Z<&f&H_vtBBuV!m`cpZ%B31R<P%VmDcy8RI!f+reQ0WSL^HbVtsLl(H2uYE2@UXugH(Xp2;pgXJ0lATEY=z'
    b'GqvtsXYV)S1IA%@@qsR!*YpR$gTtO8FL-mcDY`^;{J73<E{Z0tZ$s@9{%UbrCW~x7D#}SOD;MPd`8+SuB+2t)l+4p?7!St1*t;C1'
    b'71ldS$r?Kt#w-a%DwUOR_e7snICcDpP*4tG62Y?tBl_a_)iV^DuV0>U;jB~ps7J)B*QdXozB_ptIxceAXD?p=aQuQ-czpWHo8!|{'
    b'_z33#|M<;^YDN0*;vWLXe^61iGf?nxUVM7Iy1BS$RDl=?s3NH^ienty91}~*<aTi4t%Wee8s}I(uA={l#I);r4(K<Pz#`fUl^ruC'
    b'O=+ad&GiRWC#1|vEO;E(pRV5gUVNdq&xSPAMWnG84~f2Yg+2*I<b80dAoLl_o>t4T=ZO6J0}lltHQH=Gm|8(ab7X5wCOv{`*ym*l'
    b'VuB3b5opljS1#|t0A;t~<me?MxH*L9z-nX1S=&Zk1*3RWV>FXzrsSXfD<#2-iB7^4L7xmx29=a)OY43My(L(8No;%LW(5j8YYTbE'
    b')@2D-Pc->~ags?yWJ32RqjL4dpZ`{AGOSXJSfF+4-YD|b<qgGbK1i6Fr(AHc%4l+mLqAM<sZxfwMGNt2Z}Zk+PfJd&l8wxrUtaFn'
    b'>KU2KKtF?!O594%aW&EyA&fNTu|dGr4v%qzmAN>qD0RTC$9@Od?B~F;IqCVWy8F&BoQ_M2SqQoV^>c95h9oquH`J>JZEsP1xHE3c'
    b'2CDJE!D;FwR3Yg>cJYN-lh!2>v`K5u1_4nbcVTUuRk(M}7Yx9A@4J;&9fLJax;S+NEwTD_f;PKA<=vX{KRVpoJ0%rtBV}Ps-FY*&'
    b'>225rL}g3q8!Ulic?~!uFZx|k)-rz{9U+O06gjPk?mK&5kWLeY@qcRAM{Ry-Sgz*ovr=d_R`!6JRFc#U&sdYPw5hZ9J0HF-?$akV'
    b'WP<#H=XAXwcE~Znp8R!)1UJ~}Kb1p}c7X`r^1ATy2daJj6R87FU;p?Vd<A!fHIVgZFNA??kZp)LycrWCE$Q9!1pZ}t0@<`$C<579'
    b'*oqxcUo3wjF`&_vyT%Eqjq~@T17suf9hm@oqg|N**<hu;dJ;hPdf$QnkGz(~|JNHe;Qy<NyZQgLCT@}cj}03cVTp>VDW#uQ3FKh<'
    b'*!6big{$T7+n#OD$Kj_hu|3fD*@9J-6W+<*N0!L#viI#}L%E3iss$cK+((}OD-ri8uXj(}cTe1RH;DVHW!ap#&w5a7&)HXZvN!I~'
    b'ZcKfy?wFbW1IXXMU8+9zW-3cx+AD{X#bhv__p-d`#iJt6($TmWj~2tYH;<ESKFs^^B7mh&uAjN+2gCwQCzDZL_R4rM&W4jD&WB~1'
    b'#e;ZQr14~4F6L=E4kYN4jb_+;gK%y>rD#Z5y`0L(CtIsN(mbul<}X_i@zvJpqu*nXY{9%I+jw@;J@vuUcgOF3Jv})+yF8a5It;`)'
    b'`E5d}_-s^!e_^J+B<V!ku=UyeEP_Nuw^-ZFK`ZnsWQM*v4!xa8`rM5-<>zC=<Q^JbH|`jX+qn3yKNlCDieNH6as~vF@ilUvX<Gdj'
    b'?0Z(BVI|%(r=;HNuqV2`F!$vD4yHYs8N`sI$4{R=hq*cRKsD1&Jl}vD-p<cqe>9A#ufDA7#jF8jbxe!s=e9ENvB2N!<?5!m({zOv'
    b'RbUII!Ul|#_iTlAF!$yG(2%H5m5f_*6tYV0JUw9mF8N=Mq0l(mZik%E-pnq%ghq{frX;LC^J~}$>nr#^M1)@TxrT#~-8BD+B!tZ`'
    b'S@(Y>ea|}h7i1mWVd304uEFo~E_a$?a9bks-B||fe64>Gg25fv&@QxsTL;SAWj4XR9wXnANYLeD_}|DOxZ|d{XAZne%z-RA@}4yC'
    b'yO0KMv30&TRiMq~yH}P#zxyPBAh6y>yyph|+i(NAcg#I4U<fT>?QT;T0qeKcJsIHLB?GjZd-sHZe;OfRt?=5J3-IgZQ8cG<6XYrL'
    b'7`IWBAVHv<Zu9NdC<A4C@2;^0ayRXFr3+N-$UDmv$kr{Af@wYW^8;d4(0naTVD;oZTi`ug;5}R5oo5T&PA2@dI0DTmST8-G9@KhQ'
    b'nE~yuWs(988j=E<^@j5S>SMPhtKqG%0oJ{jiwLkL3U>b-fNppC?(~1=AZ*9{XJ;tbc|Cn6-aj4^?cmz3WBq$tVLQJ?o7zwMXM+&1'
    b'r2{yK|BMuYd-}h<(*N;bVdQ+!&Oo=H<?iwQvG=eu=UMjsJ<DGm%bzWM=AHoXZ%hD~B=<~!x6cIV*;e-?fO{eVG{<<a{C~GY=6H8V'
    b'0BcOfzcK$`h_-%D{dc#h|M1wV;dEy7fA=hbe;<}W*-vm!5P0hZfz9khP1WW%@b_eZe?v0BAS%4SC>!54^oIO`yoRjL?Of58rs>(3'
    b'dQ1uVX?ffXunH%fv6ekPwK{_9XbX291dXiF;@$!4QhQnHy8w1V4*}xemAKG0EgB`Ce@gzIbcI_Diw=<hVYoCkVF`?77hh(})e>kn'
    b'mj6>+%@Adi@^`>VM~=9Rt}t-`V!#Oo>)oul<3k6fh3F9$E<~YopWTr15DI-k-s6-d(P-M1iS8!?sh~nf&J4?1*%_kY4BDt{1r};D'
    b'WpGxg1(IPpm?4&Madkv=xi8VvB~dgW>;>o^fvq6=Do3kgkeX7*f4<C?E5s4rqPnef<6GruG9UC8<1)_XX|c%jH0vdcUf%1M#V|`2'
    b'qj?gi@nR4U$8nwy=fg!3Px^~|G4GeX#bDlQj7iAB4z-TNMUpNSqv2xIOOxTEOa{GjT;%gS?)At0-XNLxhNEOczMTxlSu)Pb7(kE4'
    b'{W2}f#lXv*L*DxkgC|%JKwHs_P1+pVLrkTw@VZ#s0M48a+E!sFtPbduZmzFx7T3{RoWoy=FGtY{-!M3J9logR`@y^35|tg$rO}2k'
    b'f=Po4nC^dw3yd!>`4g#+@(~_In?<oI-jKONljM+ojV&5XCm)L|*zS=1xOz_nLY3n5F{2!jfE!)lwJVS9rBRwFNFdS+uvTz@T>|4B'
    b'Cb<0wdG+M+AHn2c`EH_hta1V3=kjX(o@m<}2oJfNLS*|58z)Jc=aWfMjFM3?m`t)P8^#&2xyEGc^yiZ}8;uv)ycmv#lR+HA?jT!c'
    b')Ef^LgVAKXw+%b&<@3of&lZbGG9Sg0Mb=;RhxuZh<@0gBpG`8dL3_i+cv6m%L7F8+8kd8-H%TXpcpiI+w)BN7mKv<Tp}zhk*ox%}'
    b'$XsS{TC?Mb6Y5}M52Sb#aVp{u`Rxa0gBw?{WUXd2gF9AKh^jr%Bh2gJ!z;k2J81p0WdaC;*SIQwNDf+TnrPux;1dacM=Hg?g|wPF'
    b'fct9M2W87iQvrdLVkSgKA-nmi%9nLg*-$JPsW?jo3a>$33RU7YW|eh-Zz!xD0gqy-D=$6?Ni2Q6T&)9KRtM6QXjNK&!CHNt7Ax-2'
    b'G)io{;~9}rM93ZR2LV?rwnQV$7%4QQOK~s~&ONcX$d(^*7fAa?5@{|8Y$O^JX+d-Wai=&(caAJ^YjEi*xH%Aw;6t^G1dd1KhTg#n'
    b'0?O_zzuS(Slj;_drAB}VwWObj921(hfKPpobP|!gMN_x7N!*gtw(z`sQ138@BnS2h&Bd3k`lJ#Z6K8UY{e%J@87D$|<J1)`tR5=g'
    b'B6;L1s~23DV#cL}5lQDj!1ngH^MKq8H8sxETdZkua%vncQk&7cOKP02vfxa)yP6f!G?&0E<qUGRtUEPgZkvd#kZgoT;~5-(>~Zn2'
    b'Xk?aW!<ck_0`4S?99<{@dRgux)OksRkty9$7q&t)r_p@NViSQA<4JT)OppT4#!bWyMhI7CeD#b0SEkkBTxf=;-X1k;_2{}nXKj9O'
    b'Gw@f6n{8FcJ6W6?p8x2M)ed7ivs{{01!)=1nC*yBaJav#s#RXO2P!w(F|IZ;!;~LQL@A1wWjE4$df5;@Hduf#@^m+~40aoQA3g_K'
    b'XpX9av4>a|(`Y_JS|>)vxB*xXSgCM-giBDR$JLkJcHx(DXWNZgxO}wlve%ihY&kGZy%bui3xVNpk)gWTzzD5494qc-K(kq|mcVdA'
    b'9TA*g4bMJq;#IuB#@3YxjUhjeUopOW{maQKIH5(ZM3;23n{_t@sSH>Dv!Cmqa#;#8)ANt7e|_~1DoHdl>|aiPo5k>h&d(lJ?|&V?'
    b'`1OQV;CTu1Jn&<~4n2PL6dt}2ciWzJet!4v4X|VX>o?v(lkgaWUdVH&wGV#tgSyL?z%l{#-g#nglfiI58z+d6Py#fk@}onKGP1yx'
    b'$ASEN25EJ*MBzvi9s|I&ko|&VxZAy01D+QC$!M!L^b=gAb>XOG&yl9Qc+zrfJ<?hdhjG~}J?k!XDsbcnpGv<m_Ut#Lx@jvo0)>^<'
    b'ccWA>{#33ZljJR9Jl{-9@OLzB<??EMy<V&@4lyrfipNCNkoXnp$=Ng6#pmqHra?<Mf^4SN-RtcAMtnd!po<T5;h?5J<i+LnhiM|7'
    b'A}@GzwJEwp6DRuj%|+3qbqljPu^rZ5hz_3ix{J%3$7Bny-hWxHx=SJfaCU<$AI-<(-elCDrz4`Hr%7)<DdTK1C?;7R_v6uIoXvYh'
    b'Ht;S-X@&KUQnJPlhA~szrBYc5PB{AP@1ODM7Lih|b3cMNltY#Z2=jpveR2Hi8H&u;FHg8=es}WrC9vCo1bzADopwOHdVTua>ARDc'
    b'q2nT#efHw@563Tfg~zAAyg5ESg^zF=@Q>eoDCDI7XVy-hW2$OUQMEHr@Nr&zdc3;1xM);?7zwB%sV|CS9NZieOUmSSaN@0nsDl&c'
    b'SU#+x|A@r2>q-t$ZYp_2R2M2bW=xpUyr7%w52`ju+2NUw0+*kz+x%X9p^^HAFw`Zau@w)AvUP=#5Q@b6;L<<nGnOr_mSfKm@%0Cu'
    b'2{%_4hnvj@Qzan(-CUDG>(bU38<;~L>(4$fOOO&|@Qy%t7Qb?F4|m`!bAX(?WCS;d@EjOz>@;iJn08?l_rafgyUg{9IS&d5^vNKm'
    b'Z10g!H(Y56R$LOx#<*F5D$kgEVU_?Z3nFzX?!)q9f!8#!7Zw-mO;Kt6WJs>Q_#uHRErwN!86C7v-Tz9yf-59&;T<GQ!BgCutTKwp'
    b';m{0|UaFMgZP7x!+S?4j+|zoKt7Ic{$Jds7t_&1TPUa2vI5o|4Sc){03Y~g9gQ~cCk6@hKOl3|DD?GkLSr1ZKb%N9;VlWye!N2Vc'
    b'a`RT}O<xO&1b5UQnz_-q-UdE3Xnu<pnz-V&Y@!+z9HA}zglb?3NHM`U@5i=55S$ES4W$KW1HUXWu&6d8E!?^0%c9`D_r>U|enG#F'
    b'ZZvnKc(Llqy9XfY@m@{&A06)UostT+5w|d;Zt#%XbU5sS8M~Dj4i?3+yZ{^`7=5lFbeTVo4o?+Q$nLD?#q51SdW@lnx$UrLTHHa)'
    b';gyEfYTbYO`M;gkM}C*3cEj_QuPK~YSW1okwcqt1h925{x=;KL-v<xKdYH|?+?dVqc%IDw`(QR>X)fZL2figG{y(O|?(P'
)
ORIGINAL150_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity', 'NativeC2afBoundary.test_original83_complete_method_sources_are_unchanged', 'NativeC2afBoundary.test_new14_old15_history34_history19_and_original65_remain_separate', 'NativeC2afBoundary.test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources', 'NativeC2afBoundary.test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted', 'NativeC2afBoundary.test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape', 'NativeC2afBoundary.test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation', 'NativeC2afBoundary.test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse', 'NativeC2afBoundary.test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks', 'NativeC2afBoundary.test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks', 'NativeC2afBoundary.test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory', 'NativeC2afBoundary.test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer', 'NativeC2afBoundary.test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport', 'FixedPublicRepairRead.test_present_exact_3393_never_fetches', 'FixedPublicRepairRead.test_missing_3393_uses_only_separate_fixed_public_bounded_fetch', 'FixedPublicRepairRead.test_3393_network_failures_and_credential_configuration_refuse_without_retry', 'FixedPublicRepairRead.test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail', 'PortableDiagnosticBoundary.test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings', 'PortableDiagnosticBoundary.test_exact_f04_selection_source_and_four_path_layer_are_mandatory', 'PortableDiagnosticBoundary.test_all_four_actual_current_files_and_both_tree_authorities_are_strict', 'PortableDiagnosticBoundary.test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk', 'PortableDiagnosticBoundary.test_new4_and_published14_15_34_19_scope_cannot_be_relabelled', 'PortableDiagnosticBoundary.test_portable_receipt_requires_new_identity_before_original65_checks', 'FixedPublicNativeRead.test_present_c2af_never_fetches', 'FixedPublicNativeRead.test_missing_c2af_is_one_exact_bounded_public_read', 'FixedPublicNativeRead.test_bad_c2af_identity_config_timeout_and_parent_fail_closed', 'DescriptionRepairBoundary.test_complete_original108_methods_and_decorators_are_byte_identical', 'DescriptionRepairBoundary.test_original108_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'DescriptionRepairBoundary.test_new11_old4_native14_15_34_19_and_original65_stay_separate', 'DescriptionRepairBoundary.test_all_eight_current_payloads_restore_exact_complete_7b_bytes', 'DescriptionRepairBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'DescriptionRepairBoundary.test_each_of_eleven_current_files_rejects_missing_old_and_same_stat_bytes', 'DescriptionRepairBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'DescriptionRepairBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'DescriptionRepairBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'DescriptionRepairBoundary.test_every_before_and_current_tree_requires_all_eleven_exact_modes_blobs_and_types', 'DescriptionRepairBoundary.test_new11_scope_authenticates_old4_native14_and_all_older_domains', 'DescriptionRepairBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'DescriptionRepairBoundary.test_description_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'FixedPublicPortableRead.test_present_exact_f04_never_fetches_or_reads_network_configuration', 'FixedPublicPortableRead.test_missing_f04_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPortableRead.test_f04_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPortableRead.test_f04_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPortableRead.test_existing_or_fetched_f04_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPortableRead.test_fixed_f04_public_object_identity_cannot_be_generalized', 'SocialActorBoundary.test_complete_original127_methods_and_decorators_are_byte_identical', 'SocialActorBoundary.test_original127_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'SocialActorBoundary.test_new15_old11_old4_native14_15_34_19_and_original65_stay_separate', 'SocialActorBoundary.test_all_twelve_current_payloads_restore_exact_complete_42_bytes', 'SocialActorBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'SocialActorBoundary.test_each_of_fifteen_current_files_rejects_missing_old_and_same_stat_bytes', 'SocialActorBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'SocialActorBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'SocialActorBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'SocialActorBoundary.test_every_before_and_current_tree_requires_all_fifteen_exact_modes_blobs_and_types', 'SocialActorBoundary.test_new15_scope_authenticates_old11_old4_native14_and_all_older_domains', 'SocialActorBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'SocialActorBoundary.test_social_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'SocialActorBoundary.test_actor_leaf_is_only_initializer_annotation_and_equatable_identity_bytes_are_unchanged', 'SocialActorBoundary.test_merchant_single_test_leaf_matches_reviewed_complete_after_and_exact42_before', 'SocialActorBoundary.test_historical_inputs_copy_bytes_without_aliasing_any_current_checkout_file', 'SocialActorBoundary.test_new_performance_control_cannot_claim_any_historical_predecessor', 'FixedPublicDescriptionRead.test_present_exact_7b_never_fetches_or_reads_network_configuration', 'FixedPublicDescriptionRead.test_missing_7b_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicDescriptionRead.test_7b_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicDescriptionRead.test_7b_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicDescriptionRead.test_existing_or_fetched_7b_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicDescriptionRead.test_fixed_7b_public_object_identity_cannot_be_generalized')
ORIGINAL150_SOURCE_SHA256 = '80df28902ce51fddd33119ed2442b384f66e3b02375395390c4c161f98c2a71b'

def pathfix_bb5_test_source():
    import base64
    import zlib
    raw = zlib.decompress(base64.b85decode(PATHFIX_BB5_TEST_PACKED))
    if (runner.hashlib.sha256(raw).hexdigest() != PATHFIX_BB5_TEST_SHA256
            or runner.blob_id(raw) != PATHFIX_BB5_TEST_BLOB):
        raise ValueError('Changed complete bb5 historical diagnostic source')
    return raw


def original150_source_blocks(raw):
    tree = ast.parse(raw.decode('utf-8'))
    lines = raw.splitlines(keepends=True)
    found = {}
    for cls in tree.body:
        if not isinstance(cls, ast.ClassDef): continue
        for node in cls.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
            identity = cls.name + '.' + node.name
            if identity not in ORIGINAL150_IDENTITIES: continue
            if identity in found: raise ValueError('Duplicate original150 method identity')
            first = min([node.lineno] + [d.lineno for d in node.decorator_list])
            found[identity] = b''.join(lines[first - 1:node.end_lineno]).decode('utf-8')
    if len(found) != 150 or set(found) != set(ORIGINAL150_IDENTITIES):
        raise ValueError('Missing complete original150 method identity')
    return found


def verify_original150_source(raw):
    found = original150_source_blocks(raw)
    if runner.hashlib.sha256(runner.encode(found).encode()).hexdigest() != ORIGINAL150_SOURCE_SHA256:
        raise ValueError('Changed complete original150 method source bytes')
    return found


def pathfix_test_inputs(selection, current):
    """Authenticate real current3 before copying a bounded physical bb5 view."""
    runner.validate_pathfix_selection(selection, current)
    restored = runner.pathfix_predecessor_sources(selection, current)
    old = runner.pathfix_predecessor_selection(selection)
    old_selection = (json.dumps(old, indent=2, ensure_ascii=True) + '\n').encode()
    old_test = pathfix_bb5_test_source()
    if (runner.blob_id(old_selection) != runner.PATHFIX_BEFORE_BLOBS['tools/targeted_native_selection.json']
            or runner.blob_id(old_test) != runner.PATHFIX_BEFORE_BLOBS['tools/tests/test_targeted_native.py']):
        raise ValueError('Complete bb5 diagnostic predecessors not restored')
    contract = json.loads(restored['tools/run138_editor_readiness_contract.json'])
    paths = set(runner.BOUND_SOURCES) | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS)
    for values in (runner.STATIC_REPAIR_PATHS, runner.PATHS, runner.NATIVE_PATHS,
                   runner.PORTABLE_PATHS, runner.DESCRIPTION_PATHS, runner.SOCIAL_PATHS,
                   runner.PATHFIX_PATHS): paths.update(values)
    paths.update(contract['feature_batch_sources'])
    paths.update(contract['feature_batch_support_sha256'])
    paths.add('tools/run138_current_source_projection.py')
    temporary = tempfile.TemporaryDirectory(prefix='targeted-bb5-inputs-')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name)
    for relative in sorted(paths):
        source = current / relative
        parts = Path(relative).parts
        if (any((current / Path(*parts[:end])).is_symlink() for end in range(1, len(parts) + 1))
                or not source.is_file()
                or not source.resolve(strict=True).is_relative_to(current.resolve(strict=True))):
            raise ValueError('Missing or linked bb5 fixture input: ' + relative)
        raw = source.read_bytes()
        if relative in runner.PATHFIX_PAYLOAD_PATHS: raw = restored[relative]
        if relative == 'tools/targeted_native_selection.json': raw = old_selection
        elif relative == 'tools/tests/test_targeted_native.py': raw = old_test
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
    return old, root


def casefold_test_inputs(selection, current):
    """Authenticate current3, then copy a bounded physical published54 view."""
    runner.validate_casefold_selection(selection, current)
    restored = runner.casefold_predecessor_sources(selection, current)
    old = runner.casefold_predecessor_selection(selection)
    contract = runner.read_json(current / 'tools/run138_editor_readiness_contract.json')
    paths = set(runner.BOUND_SOURCES) | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS)
    for values in (runner.STATIC_REPAIR_PATHS, runner.PATHS, runner.NATIVE_PATHS,
                   runner.PORTABLE_PATHS, runner.DESCRIPTION_PATHS, runner.SOCIAL_PATHS,
                   runner.PATHFIX_PATHS): paths.update(values)
    paths.update(contract['feature_batch_sources'])
    paths.update(contract['feature_batch_support_sha256'])
    paths.add('tools/run138_current_source_projection.py')
    temporary = tempfile.TemporaryDirectory(prefix='targeted-published54-inputs-')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name)
    for relative in sorted(paths):
        source = current / relative
        parts = Path(relative).parts
        if (any((current / Path(*parts[:i])).is_symlink() for i in range(1, len(parts) + 1))
                or not source.is_file()
                or not source.resolve(strict=True).is_relative_to(current.resolve(strict=True))):
            raise ValueError('Missing or linked published54 fixture input: ' + relative)
        raw = source.read_bytes()
        if relative in restored: raw = restored[relative]
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
    return old, root


def byteperf_test_inputs(selection, current):
    """Authenticate current9, then copy a bounded physical published-c3a view."""
    runner.validate_byteperf_selection(selection, current)
    restored = runner.byteperf_predecessor_sources(selection, current)
    old = runner.byteperf_predecessor_selection(selection)
    contract = runner.read_json(current / 'tools/run138_editor_readiness_contract.json')
    paths = set(runner.BOUND_SOURCES) | set(runner.CREATOR_PATHS) | set(runner.REPAIR_PATHS)
    for values in (runner.STATIC_REPAIR_PATHS, runner.PATHS, runner.NATIVE_PATHS,
                   runner.PORTABLE_PATHS, runner.DESCRIPTION_PATHS, runner.SOCIAL_PATHS,
                   runner.PATHFIX_PATHS): paths.update(values)
    paths.update(contract['feature_batch_sources'])
    paths.update(contract['feature_batch_support_sha256'])
    paths.add('tools/run138_current_source_projection.py')
    temporary = tempfile.TemporaryDirectory(prefix='targeted-published-c3a-inputs-')
    atexit.register(temporary.cleanup)
    root = Path(temporary.name)
    for relative in sorted(paths):
        source = current / relative
        parts = Path(relative).parts
        if (any((current / Path(*parts[:i])).is_symlink() for i in range(1, len(parts) + 1))
                or not source.is_file()
                or not source.resolve(strict=True).is_relative_to(current.resolve(strict=True))):
            raise ValueError('Missing or linked published-c3a fixture input: ' + relative)
        raw = source.read_bytes()
        if relative in restored: raw = restored[relative]
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
    return old, root


MERCHANT_SOURCE = FIXTURE_PARENT_SOURCE
MERCHANT_SELECTION = runner.read_json(TOOLS / 'targeted_native_selection.json')
runner.validate_merchant_selection(MERCHANT_SELECTION, MERCHANT_SOURCE)
BYTEPERF_SOURCE = runner.merchant_history_root(MERCHANT_SELECTION, MERCHANT_SOURCE)
BYTEPERF_TOOLS = BYTEPERF_SOURCE / 'tools'
BYTEPERF_SELECTION = runner.merchant_predecessor_selection(MERCHANT_SELECTION)
runner.validate_byteperf_selection(BYTEPERF_SELECTION, BYTEPERF_SOURCE)
CASEFOLD_SELECTION, CASEFOLD_SOURCE = byteperf_test_inputs(BYTEPERF_SELECTION, BYTEPERF_SOURCE)
CASEFOLD_TOOLS = CASEFOLD_SOURCE / 'tools'
runner.validate_casefold_selection(CASEFOLD_SELECTION, CASEFOLD_SOURCE)
PATHFIX_SELECTION, PATHFIX_SOURCE = casefold_test_inputs(CASEFOLD_SELECTION, CASEFOLD_SOURCE)
PATHFIX_TOOLS = PATHFIX_SOURCE / 'tools'
runner.validate_pathfix_selection(PATHFIX_SELECTION, PATHFIX_SOURCE)
SOCIAL_SELECTION, SOCIAL_SOURCE = pathfix_test_inputs(PATHFIX_SELECTION, PATHFIX_SOURCE)
SOCIAL_TOOLS = SOCIAL_SOURCE / 'tools'
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



REVIEWED179_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity', 'NativeC2afBoundary.test_original83_complete_method_sources_are_unchanged', 'NativeC2afBoundary.test_new14_old15_history34_history19_and_original65_remain_separate', 'NativeC2afBoundary.test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources', 'NativeC2afBoundary.test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted', 'NativeC2afBoundary.test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape', 'NativeC2afBoundary.test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation', 'NativeC2afBoundary.test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse', 'NativeC2afBoundary.test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks', 'NativeC2afBoundary.test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks', 'NativeC2afBoundary.test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory', 'NativeC2afBoundary.test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer', 'NativeC2afBoundary.test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport', 'FixedPublicRepairRead.test_present_exact_3393_never_fetches', 'FixedPublicRepairRead.test_missing_3393_uses_only_separate_fixed_public_bounded_fetch', 'FixedPublicRepairRead.test_3393_network_failures_and_credential_configuration_refuse_without_retry', 'FixedPublicRepairRead.test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail', 'PortableDiagnosticBoundary.test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings', 'PortableDiagnosticBoundary.test_exact_f04_selection_source_and_four_path_layer_are_mandatory', 'PortableDiagnosticBoundary.test_all_four_actual_current_files_and_both_tree_authorities_are_strict', 'PortableDiagnosticBoundary.test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk', 'PortableDiagnosticBoundary.test_new4_and_published14_15_34_19_scope_cannot_be_relabelled', 'PortableDiagnosticBoundary.test_portable_receipt_requires_new_identity_before_original65_checks', 'FixedPublicNativeRead.test_present_c2af_never_fetches', 'FixedPublicNativeRead.test_missing_c2af_is_one_exact_bounded_public_read', 'FixedPublicNativeRead.test_bad_c2af_identity_config_timeout_and_parent_fail_closed', 'DescriptionRepairBoundary.test_complete_original108_methods_and_decorators_are_byte_identical', 'DescriptionRepairBoundary.test_original108_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'DescriptionRepairBoundary.test_new11_old4_native14_15_34_19_and_original65_stay_separate', 'DescriptionRepairBoundary.test_all_eight_current_payloads_restore_exact_complete_7b_bytes', 'DescriptionRepairBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'DescriptionRepairBoundary.test_each_of_eleven_current_files_rejects_missing_old_and_same_stat_bytes', 'DescriptionRepairBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'DescriptionRepairBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'DescriptionRepairBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'DescriptionRepairBoundary.test_every_before_and_current_tree_requires_all_eleven_exact_modes_blobs_and_types', 'DescriptionRepairBoundary.test_new11_scope_authenticates_old4_native14_and_all_older_domains', 'DescriptionRepairBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'DescriptionRepairBoundary.test_description_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'FixedPublicPortableRead.test_present_exact_f04_never_fetches_or_reads_network_configuration', 'FixedPublicPortableRead.test_missing_f04_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPortableRead.test_f04_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPortableRead.test_f04_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPortableRead.test_existing_or_fetched_f04_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPortableRead.test_fixed_f04_public_object_identity_cannot_be_generalized', 'SocialActorBoundary.test_complete_original127_methods_and_decorators_are_byte_identical', 'SocialActorBoundary.test_original127_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'SocialActorBoundary.test_new15_old11_old4_native14_15_34_19_and_original65_stay_separate', 'SocialActorBoundary.test_all_twelve_current_payloads_restore_exact_complete_42_bytes', 'SocialActorBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'SocialActorBoundary.test_each_of_fifteen_current_files_rejects_missing_old_and_same_stat_bytes', 'SocialActorBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'SocialActorBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'SocialActorBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'SocialActorBoundary.test_every_before_and_current_tree_requires_all_fifteen_exact_modes_blobs_and_types', 'SocialActorBoundary.test_new15_scope_authenticates_old11_old4_native14_and_all_older_domains', 'SocialActorBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'SocialActorBoundary.test_social_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'SocialActorBoundary.test_actor_leaf_is_only_initializer_annotation_and_equatable_identity_bytes_are_unchanged', 'SocialActorBoundary.test_merchant_single_test_leaf_matches_reviewed_complete_after_and_exact42_before', 'SocialActorBoundary.test_historical_inputs_copy_bytes_without_aliasing_any_current_checkout_file', 'SocialActorBoundary.test_new_performance_control_cannot_claim_any_historical_predecessor', 'FixedPublicDescriptionRead.test_present_exact_7b_never_fetches_or_reads_network_configuration', 'FixedPublicDescriptionRead.test_missing_7b_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicDescriptionRead.test_7b_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicDescriptionRead.test_7b_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicDescriptionRead.test_existing_or_fetched_7b_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicDescriptionRead.test_fixed_7b_public_object_identity_cannot_be_generalized', 'PathTemplateDiagnosticBoundary.test_original150_complete_method_bytes_and_decorators_are_unchanged', 'PathTemplateDiagnosticBoundary.test_original150_source_identity_rejects_body_comment_missing_and_duplicate_method', 'PathTemplateDiagnosticBoundary.test_complete_bb5_predecessor_json_and_test_bytes_are_fixed', 'PathTemplateDiagnosticBoundary.test_all_three_current_raw_files_reject_missing_old_same_size_mtime_and_links_after_warm', 'PathTemplateDiagnosticBoundary.test_noncanonical_selection_bytes_and_unknown_or_missing_layer_are_rejected', 'PathTemplateDiagnosticBoundary.test_missing_foreign_source_never_falls_back_to_loaded_healthy_root', 'PathTemplateDiagnosticBoundary.test_parent_directory_symlink_is_rejected_even_for_byte_identical_inputs', 'PathTemplateDiagnosticBoundary.test_historical_fixture_has_no_hardlink_into_real_current_source', 'PathTemplateDiagnosticBoundary.test_coherent_outer_repin_cannot_change_before_blobs_or_any_historical_selection_byte', 'PathTemplateDiagnosticBoundary.test_exact_new3_scope_preserves_all_published_fifteen_and_older_layers', 'PathTemplateDiagnosticBoundary.test_scope_rejects_new_parent_merge_mode_missing_extra_and_every_old_scope', 'PathTemplateDiagnosticBoundary.test_receipt_requires_pathfix_and_every_old_identity_and_all65_real_results', 'XctestrunPathTemplateTests.test_plain_and_double_underscore_product_root_aliases', 'XctestrunPathTemplateTests.test_literal_token_product_roots_are_not_reexpanded', 'XctestrunPathTemplateTests.test_double_underscore_product_children_and_absolute_paths', 'XctestrunPathTemplateTests.test_nested_host_tokens_preserve_literal_physical_root_names', 'XctestrunPathTemplateTests.test_unknown_template_tokens_reject_existing_literal_paths', 'XctestrunPathTemplateTests.test_missing_empty_and_recursive_host_tokens_reject', 'XctestrunPathTemplateTests.test_relative_and_missing_product_fields_reject', 'XctestrunPathTemplateTests.test_parent_and_absolute_sibling_escapes_reject', 'XctestrunPathTemplateTests.test_product_links_stay_inside_root_and_run_links_reject', 'XctestrunPathTemplateTests.test_multiple_runs_extra_targets_and_no_match_reject', 'XctestrunPathTemplateTests.test_non_token_double_underscore_names_remain_literal', 'FixedPublicSocialRead.test_present_exact_42_never_fetches_or_reads_network_configuration', 'FixedPublicSocialRead.test_missing_42_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicSocialRead.test_42_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicSocialRead.test_42_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicSocialRead.test_existing_or_fetched_42_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicSocialRead.test_fixed_42_public_object_identity_cannot_be_generalized')
REVIEWED179_SOURCE_SHA256 = '095f14d01c4c6929319b8cbfb31adfc57a0fd3c27bcdb0d311a2004fc5623ad4'

class PathTemplateDiagnosticBoundary(unittest.TestCase):
    """Current3 source controls; Apple execution is a separate workflow result."""
    def fixture_root(self):
        temporary = tempfile.TemporaryDirectory(prefix='pathfix-three-controls-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for relative in runner.PATHFIX_PATHS:
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((PATHFIX_SOURCE / relative).read_bytes())
        return root

    def test_original150_complete_method_bytes_and_decorators_are_unchanged(self):
        old = pathfix_bb5_test_source()
        current = (PATHFIX_SOURCE / 'tools/tests/test_targeted_native.py').read_bytes()
        self.assertEqual(verify_original150_source(current), verify_original150_source(old))
        self.assertEqual(len(original150_source_blocks(old)), 150)

    def test_original150_source_identity_rejects_body_comment_missing_and_duplicate_method(self):
        raw = pathfix_bb5_test_source()
        first = next(iter(original150_source_blocks(raw).values())).encode()
        variants = (raw.replace(first, b'', 1),
                    raw.replace(first, first + b'\n' + first, 1),
                    raw.replace(first, first.replace(b'    def ', b'    def changed_', 1), 1),
                    raw.replace(first, first.replace(b'\n', b'\n        # changed original method byte\n', 1), 1))
        for changed in variants:
            with self.assertRaises(ValueError): verify_original150_source(changed)
        self.assertEqual(verify_original150_source(raw), original150_source_blocks(raw))

    def test_complete_bb5_predecessor_json_and_test_bytes_are_fixed(self):
        old = runner.pathfix_predecessor_selection(PATHFIX_SELECTION)
        raw = (json.dumps(old, indent=2, ensure_ascii=True) + '\n').encode()
        self.assertEqual(old, SOCIAL_SELECTION)
        self.assertEqual(runner.blob_id(raw), runner.PATHFIX_BEFORE_BLOBS['tools/targeted_native_selection.json'])
        self.assertEqual(runner.blob_id(pathfix_bb5_test_source()),
                         runner.PATHFIX_BEFORE_BLOBS['tools/tests/test_targeted_native.py'])
        self.assertEqual(runner.validate_pathfix_selection(PATHFIX_SELECTION, PATHFIX_SOURCE), PATHFIX_SELECTION)

    def test_all_three_current_raw_files_reject_missing_old_same_size_mtime_and_links_after_warm(self):
        root = self.fixture_root()
        runner.pathfix_current_inputs(PATHFIX_SELECTION, root)
        for relative in runner.PATHFIX_PATHS:
            path = root / relative
            before = path.read_bytes(); stamp = path.stat()
            with self.subTest(path=relative, mode='same-size-mtime'):
                path.write_bytes(bytes([before[0] ^ 1]) + before[1:])
                os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
                with self.assertRaises(ValueError): runner.pathfix_current_inputs(PATHFIX_SELECTION, root)
                path.write_bytes(before)
            with self.subTest(path=relative, mode='missing'):
                path.unlink()
                with self.assertRaises((ValueError, OSError)): runner.pathfix_current_inputs(PATHFIX_SELECTION, root)
                path.write_bytes(before)
            with self.subTest(path=relative, mode='leaf-symlink'):
                path.unlink(); path.symlink_to(PATHFIX_SOURCE / relative)
                with self.assertRaises((ValueError, OSError)): runner.pathfix_current_inputs(PATHFIX_SELECTION, root)
                path.unlink(); path.write_bytes(before)
        for relative, old in [('tools/targeted_native_selection.json', (json.dumps(SOCIAL_SELECTION, indent=2, ensure_ascii=True)+'\n').encode()),
                              ('tools/tests/test_targeted_native.py', pathfix_bb5_test_source())]:
            path = root / relative; before = path.read_bytes(); path.write_bytes(old)
            with self.subTest(path=relative, mode='old'), self.assertRaises(ValueError):
                runner.pathfix_current_inputs(PATHFIX_SELECTION, root)
            path.write_bytes(before)
        runner.pathfix_current_inputs(PATHFIX_SELECTION, root)

    def test_noncanonical_selection_bytes_and_unknown_or_missing_layer_are_rejected(self):
        root = self.fixture_root(); path = root / 'tools/targeted_native_selection.json'; before = path.read_bytes()
        for raw in (before+b'\n', before.replace(b'\n', b'\r\n'), json.dumps(PATHFIX_SELECTION).encode()):
            path.write_bytes(raw)
            with self.assertRaises(ValueError): runner.pathfix_current_inputs(PATHFIX_SELECTION, root)
        path.write_bytes(before)
        for value in ({}, SOCIAL_SELECTION, dict(PATHFIX_SELECTION, unreviewed=True)):
            with self.assertRaises(ValueError): runner.pathfix_predecessor_selection(value)

    def test_missing_foreign_source_never_falls_back_to_loaded_healthy_root(self):
        with tempfile.TemporaryDirectory(prefix='pathfix-empty-controls-') as temporary:
            with self.assertRaises((ValueError, OSError)):
                runner.validate_pathfix_selection(PATHFIX_SELECTION, Path(temporary))

    def test_parent_directory_symlink_is_rejected_even_for_byte_identical_inputs(self):
        root = self.fixture_root()
        import shutil
        shutil.rmtree(root / 'tools')
        (root / 'tools').symlink_to(PATHFIX_SOURCE / 'tools', target_is_directory=True)
        with self.assertRaises((ValueError, OSError)):
            runner.pathfix_current_inputs(PATHFIX_SELECTION, root)

    def test_historical_fixture_has_no_hardlink_into_real_current_source(self):
        for relative in ('App/ProjectThoughtDefinitionsEditor.swift', 'tools/run138_current_source_projection.py',
                         'tools/run_targeted_native.py', 'tools/tests/test_targeted_native.py'):
            current = PATHFIX_SOURCE / relative; historical = SOCIAL_SOURCE / relative
            self.assertFalse(os.path.samefile(current, historical), relative)
            self.assertEqual(current.stat().st_nlink, 1, relative)
            self.assertEqual(historical.stat().st_nlink, 1, relative)

    def test_coherent_outer_repin_cannot_change_before_blobs_or_any_historical_selection_byte(self):
        root = self.fixture_root()
        import contextlib
        for kind in ('before-blob', 'old-field'):
            changed = copy.deepcopy(PATHFIX_SELECTION)
            if kind == 'before-blob':
                changed['xctestrun_path_repair']['diagnostic_before_blobs'][runner.PATHFIX_PATHS[0]] = '0' * 40
            else:
                changed['unreviewed_historical_field'] = True
            raw = (json.dumps(changed, indent=2, ensure_ascii=True) + '\n').encode()
            (root / 'tools/targeted_native_selection.json').write_bytes(raw)
            with self.subTest(kind=kind), \
                 mock.patch.object(runner, 'PATHFIX_LAYER', changed['xctestrun_path_repair']), \
                 mock.patch.object(runner, 'PATHFIX_SELECTION_SHA256', runner.hashlib.sha256(runner.encode(changed).encode()).hexdigest()), \
                 mock.patch.object(runner, 'PATHFIX_SELECTION_RAW_SHA256', runner.hashlib.sha256(raw).hexdigest()), self.assertRaises(ValueError):
                runner.pathfix_current_inputs(changed, root)

    def transport(self, command, root):
        """Explicit synthetic transport, separate from real Git scope verification."""
        if command[1:3] == ['rev-parse', runner.PATHFIX_BASE_COMMIT + '^{tree}']:
            return runner.PATHFIX_BASE_TREE
        if command[1:3] == ['cat-file', '-p']:
            if command[3] == 'a' * 40:
                return 'tree ' + 'b' * 40 + '\nparent ' + runner.PATHFIX_BASE_COMMIT + '\n\nSynthetic new3 metadata'
            if command[3] == runner.PATHFIX_BASE_COMMIT:
                return 'tree ' + runner.PATHFIX_BASE_TREE + '\nparent ' + runner.SOCIAL_BASE_COMMIT + '\n\nPublished bb5 metadata mock'
        if command[1] == 'diff' and command[3] == runner.PATHFIX_BASE_COMMIT:
            return '\n'.join(runner.PATHFIX_LAYER['allowed_changes'])
        if command[1] == 'ls-tree':
            if tuple(command[5:]) == runner.PATHFIX_PATHS:
                expected = runner.PATHFIX_BEFORE_BLOBS if command[3] == runner.PATHFIX_BASE_COMMIT else {
                    path: runner.blob_id((root / path).read_bytes()) for path in runner.PATHFIX_PATHS}
                return '\0'.join('100644 blob ' + blob + '\t' + path for path, blob in expected.items()) + '\0'
            if tuple(command[5:]) == runner.SOCIAL_PATHS and command[3] == runner.PATHFIX_BASE_COMMIT:
                return '\0'.join('100644 blob ' + blob + '\t' + path
                                 for path, blob in runner.PATHFIX_SOCIAL_AFTER_BLOBS.items()) + '\0'
        return SocialActorBoundary().transport(command, SOCIAL_SOURCE)

    def test_exact_new3_scope_preserves_all_published_fifteen_and_older_layers(self):
        calls = []
        def transport(command, root):
            calls.append(command)
            return self.transport(command, root)
        with mock.patch.object(runner, 'checked', side_effect=transport), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}):
            identity = runner.verify_pathfix_scope(PATHFIX_SOURCE, PATHFIX_SELECTION)
        self.assertEqual(identity['source_sha'], 'a' * 40)
        self.assertEqual(identity['source_tree'], 'b' * 40)
        self.assertEqual(identity['pathfix_base_commit'], runner.PATHFIX_BASE_COMMIT)
        self.assertEqual(identity['pathfix_base_tree'], runner.PATHFIX_BASE_TREE)
        self.assertEqual({command[3] for command in calls if command[1] == 'diff'},
                         {runner.PATHFIX_BASE_COMMIT, runner.SOCIAL_BASE_COMMIT, runner.DESCRIPTION_BASE_COMMIT,
                          runner.PORTABLE_BASE_COMMIT, runner.NATIVE_BASE_COMMIT, runner.BASE_COMMIT,
                          runner.CREATOR_COMMIT, runner.HISTORICAL_BASE_COMMIT})

    def test_scope_rejects_new_parent_merge_mode_missing_extra_and_every_old_scope(self):
        for mode in ('parent', 'merge', 'base-tree', 'base-parent', 'missing', 'extra', 'duplicate', 'status',
                     'mode', 'dirty', 'sha', 'old15', 'old11', 'old4', 'old14', 'old-repair15', 'old34', 'old19'):
            def changed(command, root):
                value = self.transport(command, root)
                if command[1:4] == ['cat-file', '-p', 'a' * 40]:
                    if mode == 'parent': return value.replace(runner.PATHFIX_BASE_COMMIT, runner.SOCIAL_BASE_COMMIT)
                    if mode == 'merge': return value.replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n')
                if command[1:4] == ['cat-file', '-p', runner.PATHFIX_BASE_COMMIT] and mode == 'base-parent':
                    return value.replace(runner.SOCIAL_BASE_COMMIT, runner.DESCRIPTION_BASE_COMMIT)
                if command[1:3] == ['rev-parse', runner.PATHFIX_BASE_COMMIT + '^{tree}'] and mode == 'base-tree': return '0' * 40
                if command[1:3] == ['rev-parse', 'HEAD'] and mode == 'sha': return 'f' * 40
                if command[1] == 'diff':
                    if command[3] == runner.PATHFIX_BASE_COMMIT:
                        if mode == 'missing': return '\n'.join(value.splitlines()[:-1])
                        if mode == 'extra': return value + '\nM\tApp/Unexpected.swift'
                        if mode == 'duplicate': return value + '\n' + value.splitlines()[0]
                        if mode == 'status': return value.replace('M\t', 'A\t', 1)
                    if (mode, command[3]) in [('old15', runner.SOCIAL_BASE_COMMIT), ('old11', runner.DESCRIPTION_BASE_COMMIT),
                                             ('old4', runner.PORTABLE_BASE_COMMIT), ('old14', runner.NATIVE_BASE_COMMIT),
                                             ('old-repair15', runner.BASE_COMMIT), ('old34', runner.CREATOR_COMMIT),
                                             ('old19', runner.HISTORICAL_BASE_COMMIT)]: return ''
                if command[1] == 'ls-tree' and tuple(command[5:]) == runner.PATHFIX_PATHS and mode == 'mode':
                    return value.replace('100644', '100755', 1)
                if command[1] == 'status' and mode == 'dirty': return ' M App/Unexpected.swift'
                return value
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=changed), \
                 mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), self.assertRaises(ValueError):
                runner.verify_pathfix_scope(PATHFIX_SOURCE, PATHFIX_SELECTION)

    def test_receipt_requires_pathfix_and_every_old_identity_and_all65_real_results(self):
        receipt, expected = ReceiptIdentity().receipt()
        receipt.update(native_base_commit=runner.NATIVE_BASE_COMMIT, native_base_tree=runner.NATIVE_BASE_TREE,
                       native_selection=runner.NATIVE_NAME, portable_base_commit=runner.PORTABLE_BASE_COMMIT,
                       portable_base_tree=runner.PORTABLE_BASE_TREE, portable_selection=runner.PORTABLE_LAYER['name'],
                       description_base_commit=runner.DESCRIPTION_BASE_COMMIT, description_base_tree=runner.DESCRIPTION_BASE_TREE,
                       description_selection=runner.DESCRIPTION_LAYER['name'], social_base_commit=runner.SOCIAL_BASE_COMMIT,
                       social_base_tree=runner.SOCIAL_BASE_TREE, social_selection=runner.SOCIAL_LAYER['name'])
        with self.assertRaises(ValueError): runner.validate_pathfix_pass_receipt(receipt, expected, PATHFIX_SELECTION)
        receipt.update(pathfix_base_commit=runner.PATHFIX_BASE_COMMIT, pathfix_base_tree=runner.PATHFIX_BASE_TREE,
                       pathfix_selection=runner.PATHFIX_NAME)
        runner.validate_pathfix_pass_receipt(receipt, expected, PATHFIX_SELECTION)
        for field in ('pathfix_base_commit', 'pathfix_base_tree', 'pathfix_selection', 'social_base_commit',
                      'description_base_commit', 'portable_base_commit', 'native_base_commit'):
            bad = copy.deepcopy(receipt); bad[field] = 'wrong'
            with self.subTest(field=field), self.assertRaises(ValueError):
                runner.validate_pathfix_pass_receipt(bad, expected, PATHFIX_SELECTION)
        bad = copy.deepcopy(receipt); bad['groups']['core']['actual'] = []
        with self.assertRaises(ValueError): runner.validate_pathfix_pass_receipt(bad, expected, PATHFIX_SELECTION)

class XctestrunPathTemplateTests(unittest.TestCase):
    """Real filesystem controls for original-template-only xctestrun expansion."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='xctestrun-path-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def _products(self, name):
        products = Path(tempfile.mkdtemp(prefix='case-', dir=self.root)) / name
        products.mkdir(parents=True)
        return products

    def _plain(self, products, child=''):
        bundle = products / child / 'QuestifyUITests.xctest'
        bundle.mkdir(parents=True)
        return {'TestBundlePath': '__TESTROOT__/' + (child + '/' if child else '') + bundle.name}

    def _hosted(self, products):
        host = products / 'Debug__Build/Questify__Dev.app'
        (host / 'PlugIns/QuestifyAppUnitTests.xctest').mkdir(parents=True)
        (products / 'App__Build/Questify.app').mkdir(parents=True)
        return {'TestBundlePath': '__TESTHOST__/PlugIns/QuestifyAppUnitTests.xctest',
                'TestHostPath': '__TESTROOT__/Debug__Build/Questify__Dev.app',
                'UITargetAppPath': '__TESTROOT__/App__Build/Questify.app'}

    def _write_run(self, products, record, name='selected.xctestrun', extra=None):
        run = products / name
        run.write_bytes(plistlib.dumps({'tests': [record] + (extra or [])}))
        return run

    def test_plain_and_double_underscore_product_root_aliases(self):
        for name in ('plain-root', 'safe-double__underscore'):
            with self.subTest(name=name):
                products = self._products(name)
                run = self._write_run(products, self._plain(products))
                alias = self.root / (name + '-alias')
                alias.symlink_to(products, target_is_directory=True)
                self.assertEqual(runner.select_xctestrun(alias, 'QuestifyUITests'), run.resolve())

    def test_literal_token_product_roots_are_not_reexpanded(self):
        for token in ('__TESTROOT__', '__TESTHOST__', '__UNKNOWN__', '__UNKNOWN_2__'):
            with self.subTest(token=token):
                products = self._products('physical-' + token)
                run = self._write_run(products, self._plain(products))
                self.assertEqual(runner.select_xctestrun(products, 'QuestifyUITests'), run.resolve())

    def test_double_underscore_product_children_and_absolute_paths(self):
        products = self._products('absolute-double__underscore')
        record = self._plain(products, 'child__with__underscores')
        run = self._write_run(products, record)
        self.assertEqual(runner.select_xctestrun(products, 'QuestifyUITests'), run.resolve())
        record['TestBundlePath'] = str(products / 'child__with__underscores/QuestifyUITests.xctest')
        self._write_run(products, record)
        self.assertEqual(runner.select_xctestrun(products, 'QuestifyUITests'), run.resolve())

    def test_nested_host_tokens_preserve_literal_physical_root_names(self):
        for name in ('plain-host', 'double__underscore-host',
                     'physical-__TESTROOT__', 'physical-__TESTHOST__', 'physical-__UNKNOWN__'):
            with self.subTest(name=name):
                products = self._products(name)
                run = self._write_run(products, self._hosted(products))
                self.assertEqual(runner.select_xctestrun(products, 'QuestifyAppUnitTests'), run.resolve())

    def test_unknown_template_tokens_reject_existing_literal_paths(self):
        for token in ('__UNKNOWN__', '__UNKNOWN_2__', '__PLATFORMS__', '__TESTBUNDLE__'):
            with self.subTest(token=token):
                products = self._products('unknown-bundle-' + token)
                run = self._write_run(products, self._plain(products, token))
                with self.assertRaisesRegex(ValueError, 'Unresolved test product path'):
                    runner.select_xctestrun(products, 'QuestifyUITests')
        for key in ('TestHostPath', 'UITargetAppPath'):
            with self.subTest(key=key):
                products = self._products('unknown-' + key)
                record = self._plain(products)
                (products / '__UNKNOWN__/Questify.app').mkdir(parents=True)
                record[key] = '__TESTROOT__/__UNKNOWN__/Questify.app'
                self._write_run(products, record)
                with self.assertRaisesRegex(ValueError, 'Unresolved test product path'):
                    runner.select_xctestrun(products, 'QuestifyUITests')
        products = self._products('nested-unknown')
        (products / '__UNKNOWN__/Questify.app/PlugIns/QuestifyAppUnitTests.xctest').mkdir(parents=True)
        self._write_run(products, {
            'TestBundlePath': '__TESTHOST__/PlugIns/QuestifyAppUnitTests.xctest',
            'TestHostPath': '__TESTROOT__/__UNKNOWN__/Questify.app'})
        with self.assertRaisesRegex(ValueError, 'Unresolved test product path'):
            runner.select_xctestrun(products, 'QuestifyAppUnitTests')

    def test_missing_empty_and_recursive_host_tokens_reject(self):
        for mode in ('missing', 'empty', 'recursive'):
            with self.subTest(mode=mode):
                products = self._products('host-' + mode)
                record = self._plain(products)
                record['TestBundlePath'] = '__TESTHOST__' + str(products / 'QuestifyUITests.xctest')
                if mode == 'empty':
                    record['TestHostPath'] = ''
                elif mode == 'recursive':
                    record['TestHostPath'] = '__TESTHOST__/Questify.app'
                self._write_run(products, record)
                with self.assertRaisesRegex(ValueError, 'Unresolved test product path'):
                    runner.select_xctestrun(products, 'QuestifyUITests')

    def test_relative_and_missing_product_fields_reject(self):
        for key in ('TestBundlePath', 'TestHostPath', 'UITargetAppPath'):
            for mode in ('relative', 'missing'):
                with self.subTest(key=key, mode=mode):
                    products = self._products(mode + '-' + key)
                    record = self._plain(products)
                    leaf = 'QuestifyUITests.xctest' if key == 'TestBundlePath' else 'Questify.app'
                    record[key] = leaf if mode == 'relative' else '__TESTROOT__/missing/' + leaf
                    self._write_run(products, record)
                    with self.assertRaises(ValueError):
                        runner.select_xctestrun(products, 'QuestifyUITests')

    def test_parent_and_absolute_sibling_escapes_reject(self):
        for key in ('TestBundlePath', 'TestHostPath', 'UITargetAppPath'):
            for mode in ('parent', 'absolute'):
                with self.subTest(key=key, mode=mode):
                    products = self._products(mode + '-' + key)
                    record = self._plain(products)
                    leaf = 'QuestifyUITests.xctest' if key == 'TestBundlePath' else 'Questify.app'
                    outside = products.parent / (products.name + '-evil') / leaf
                    outside.mkdir(parents=True)
                    record[key] = ('__TESTROOT__/../' + outside.parent.name + '/' + leaf
                                   if mode == 'parent' else str(outside))
                    self._write_run(products, record)
                    with self.assertRaisesRegex(ValueError, 'Test product escaped build root'):
                        runner.select_xctestrun(products, 'QuestifyUITests')

    def test_product_links_stay_inside_root_and_run_links_reject(self):
        products = self._products('safe-product-link')
        (products / 'real-bundle').mkdir()
        (products / 'QuestifyUITests.xctest').symlink_to(products / 'real-bundle', target_is_directory=True)
        run = self._write_run(products, {'TestBundlePath': '__TESTROOT__/QuestifyUITests.xctest'})
        self.assertEqual(runner.select_xctestrun(products, 'QuestifyUITests'), run.resolve())
        (products / 'linked.xctestrun').symlink_to(run)
        with self.assertRaisesRegex(ValueError, 'Linked xctestrun forbidden'):
            runner.select_xctestrun(products, 'QuestifyUITests')
        for key in ('TestBundlePath', 'TestHostPath', 'UITargetAppPath'):
            with self.subTest(key=key):
                products = self._products('escaping-link-' + key)
                record = self._plain(products)
                leaf = 'QuestifyUITests.xctest' if key == 'TestBundlePath' else 'Questify.app'
                outside = self.root / ('outside-' + key)
                (outside / leaf).mkdir(parents=True)
                (products / 'linked').symlink_to(outside, target_is_directory=True)
                record[key] = '__TESTROOT__/linked/' + leaf
                self._write_run(products, record)
                with self.assertRaisesRegex(ValueError, 'Test product escaped build root'):
                    runner.select_xctestrun(products, 'QuestifyUITests')

    def test_multiple_runs_extra_targets_and_no_match_reject(self):
        products = self._products('multiple-runs')
        record = self._plain(products)
        self._write_run(products, record)
        self._write_run(products, record, name='second.xctestrun')
        with self.assertRaisesRegex(ValueError, 'Expected exactly one matching xctestrun'):
            runner.select_xctestrun(products, 'QuestifyUITests')
        products = self._products('extra-target')
        record = self._plain(products)
        (products / 'Other.xctest').mkdir()
        self._write_run(products, record, extra=[{'TestBundlePath': '__TESTROOT__/Other.xctest'}])
        with self.assertRaisesRegex(ValueError, 'Unexpected extra test target'):
            runner.select_xctestrun(products, 'QuestifyUITests')
        products = self._products('no-match')
        self._write_run(products, self._plain(products))
        with self.assertRaisesRegex(ValueError, 'Expected exactly one matching xctestrun'):
            runner.select_xctestrun(products, 'Other')

    def test_non_token_double_underscore_names_remain_literal(self):
        for child in ('name__unfinished', 'name__UNFINISHED', 'double__underscore__path'):
            with self.subTest(child=child):
                products = self._products(child)
                run = self._write_run(products, self._plain(products, child))
                self.assertEqual(runner.select_xctestrun(products, 'QuestifyUITests'), run.resolve())

class FixedPublicSocialRead(unittest.TestCase):
    """Mocked public-read boundaries only; these tests perform no network fetch."""
    def headers(self):
        return 'tree ' + runner.SOCIAL_BASE_TREE + '\nparent ' + runner.DESCRIPTION_BASE_COMMIT + '\n\nSynthetic 42 metadata'

    def present(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        if command == ['git', 'cat-file', '-p', runner.SOCIAL_BASE_COMMIT]: return self.headers()
        raise AssertionError(command)

    def missing(self, command, root):
        if command[1:3] == ['cat-file', '-e']: raise ValueError('Synthetic missing fixed 42 object')
        return self.present(command, root)

    def test_present_exact_42_never_fetches_or_reads_network_configuration(self):
        with mock.patch.object(runner, 'checked', side_effect=self.present), mock.patch.object(runner, 'execute') as execute:
            runner.ensure_social_commit(PATHFIX_SOURCE)
        execute.assert_not_called()

    def test_missing_42_uses_one_exact_bounded_noninteractive_public_read_without_credentials(self):
        environment = {'GITHUB_TOKEN': 'synthetic-not-a-secret', 'GH_TOKEN': 'synthetic-not-a-secret',
                       'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'http.extraHeader',
                       'GIT_CONFIG_VALUE_0': 'synthetic-not-a-secret', 'GIT_SSH_COMMAND': 'unexpected',
                       'HTTP_PROXY': 'http://example.invalid', 'HTTPS_PROXY': 'http://example.invalid'}
        with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', side_effect=self.missing), \
             mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute:
            runner.ensure_social_commit(PATHFIX_SOURCE)
        self.assertEqual(execute.call_count, 2)
        config, fetch = execute.call_args_list
        self.assertEqual(config.args[0], ['git', 'config', '--local', '--includes', '--name-only', '--list'])
        self.assertEqual(config.args[2], 10)
        self.assertEqual(fetch.args[0], ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                                       '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                                       '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                                       'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                                       'https://github.com/liboyang42-cpu/chengyin-ios.git',
                                       '42f69c95bb2ade207eda478e87c602b01ab6d30c'])
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

    def test_42_credential_redirect_include_and_auth_configuration_fail_before_fetch(self):
        keys = ('credential.helper', 'credential.https://github.com.username', 'http.extraheader',
                'http.https://github.com/.extraheader', 'http.proxy', 'url.ssh://example.invalid.insteadof',
                'include.path', 'includeif.gitdir:work.path', 'core.askpass', 'extensions.worktreeconfig')
        for key in keys:
            with self.subTest(key=key), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', return_value=(0, (key + '\n').encode())) as execute, self.assertRaises(ValueError):
                runner.ensure_social_commit(PATHFIX_SOURCE)
            self.assertEqual(execute.call_count, 1)

    def test_42_unreadable_config_offline_and_timeout_fail_closed_without_retry(self):
        for mode in ('config', 'offline', 'timeout'):
            outputs = [(1, b'')] if mode == 'config' else [(0, b'core.bare\n'), (124 if mode == 'timeout' else 1, b'')]
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', side_effect=outputs) as execute, self.assertRaises(ValueError):
                runner.ensure_social_commit(PATHFIX_SOURCE)
            self.assertEqual(execute.call_count, 1 if mode == 'config' else 2)

    def test_existing_or_fetched_42_wrong_tree_parent_merge_or_missing_headers_fail(self):
        bad_headers = (self.headers().replace(runner.SOCIAL_BASE_TREE, '0' * 40),
                       self.headers().replace(runner.DESCRIPTION_BASE_COMMIT, runner.BASE_COMMIT),
                       self.headers().replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n'),
                       self.headers().replace('tree ' + runner.SOCIAL_BASE_TREE + '\n', ''),
                       self.headers().replace('parent ' + runner.DESCRIPTION_BASE_COMMIT + '\n', ''),
                       self.headers().replace('\nparent ', '\ntree ' + runner.SOCIAL_BASE_TREE + '\nparent ', 1))
        for existing in (True, False):
            for bad in bad_headers:
                def read(command, root):
                    if command[1:3] == ['cat-file', '-e']:
                        if existing: return ''
                        raise ValueError('Synthetic missing 42')
                    return bad
                with self.subTest(existing=existing, headers=bad), mock.patch.object(runner, 'checked', side_effect=read), \
                     mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute, self.assertRaises(ValueError):
                    runner.ensure_social_commit(PATHFIX_SOURCE)
                self.assertEqual(execute.call_count, 0 if existing else 2)

    def test_fixed_42_public_object_identity_cannot_be_generalized(self):
        for key in ('SOCIAL_BASE_COMMIT', 'SOCIAL_BASE_TREE'):
            with self.subTest(key=key), mock.patch.object(runner, key, '0' * 40), \
                 mock.patch.object(runner, 'checked') as read, mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_social_commit(PATHFIX_SOURCE)
            read.assert_not_called(); execute.assert_not_called()




class AlbumGetterActorBoundary(unittest.TestCase):
    def test_all179_previously_reviewed_method_bytes_remain_exact(self):
        raw = (PATHFIX_SOURCE / 'tools/tests/test_targeted_native.py').read_bytes()
        lines = raw.splitlines(keepends=True); found = {}
        for cls in ast.parse(raw.decode()).body:
            if not isinstance(cls, ast.ClassDef): continue
            for node in cls.body:
                if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
                identity = cls.name + '.' + node.name
                if identity not in REVIEWED179_IDENTITIES: continue
                self.assertNotIn(identity, found)
                first = min([node.lineno] + [d.lineno for d in node.decorator_list])
                found[identity] = b''.join(lines[first - 1:node.end_lineno]).decode()
        self.assertEqual(set(found), set(REVIEWED179_IDENTITIES))
        self.assertEqual(len(found), 179)
        self.assertEqual(runner.hashlib.sha256(runner.encode(found).encode()).hexdigest(), REVIEWED179_SOURCE_SHA256)

    def test_exact_eight_payloads_restore_bb5_and_keep_all_other_files_out(self):
        expected = {'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift',
                    'tools/run138_editor_readiness_contract.json', 'tools/run138_editor_readiness.py',
                    'Tests/ContractChecks/test_category_roam_registration.py',
                    'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
                    'Tests/ContractChecks/test_global_search_category_recovery.py',
                    'tools/club_customer_directory_admission.py', 'tools/tests/test_readiness_contract_parse_cache.py'}
        self.assertEqual(set(runner.PATHFIX_PAYLOAD_PATHS), expected)
        self.assertEqual(len(runner.PATHFIX_PATHS), 11)
        root = PathTemplateDiagnosticBoundary.fixture_root(self)
        restored = runner.pathfix_predecessor_sources(PATHFIX_SELECTION, root)
        self.assertEqual(set(restored), set(runner.PATHFIX_PATHS))
        for path in expected:
            self.assertEqual(runner.blob_id(restored[path]), runner.PATHFIX_BEFORE_BLOBS[path])
        for excluded in ('tools/run138_current_source_projection.py', 'Questify.xcodeproj/project.pbxproj',
                         'tools/tests/test_run138_current_ci_entry.py', '.github/workflows/native-targeted.yml'):
            self.assertNotIn(excluded, runner.PATHFIX_PATHS)

    def test_only_actor_annotation_changes_and_all_nine_swift_methods_stay_intact(self):
        root = PathTemplateDiagnosticBoundary.fixture_root(self)
        relative = 'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift'
        restored = runner.pathfix_predecessor_sources(PATHFIX_SELECTION, root)[relative]
        raw = (root / relative).read_bytes()
        before = b'        var chapterID: String { editor.draft.chapters[0].id }'
        after = b'        @MainActor var chapterID: String { editor.draft.chapters[0].id }'
        self.assertEqual(raw.count(after), 1)
        self.assertEqual(raw.replace(after, before, 1), restored)
        self.assertEqual(runner.hashlib.sha256(restored).hexdigest(), '3d3c8ef9236f3d5a0c2b99c9eb6ce2b57c3afc36aaabdd701d1597855f024257')
        self.assertEqual(runner.hashlib.sha256(raw).hexdigest(), '5c74526f40c44327ec68254de76bd4c316e976b5aa1f6a409502774402699054')
        self.assertEqual(len(re.findall(rb'^    func test', raw, re.MULTILINE)), 9)
        for bad in (restored, raw.replace(b'editor.draft.chapters[0].id', b'"weakened"', 1),
                    raw.replace(b'XCTAssertNil', b'XCTAssertNotNil', 1)):
            (root / relative).write_bytes(bad)
            with self.assertRaises(ValueError): runner.pathfix_current_inputs(PATHFIX_SELECTION, root)
        (root / relative).write_bytes(raw)
        runner.pathfix_current_inputs(PATHFIX_SELECTION, root)

    def test_payload_rows_cannot_omit_duplicate_reorder_or_coherently_replace_preimages(self):
        changes = PATHFIX_SELECTION['xctestrun_path_repair']['payload_changes']
        variants = [changes[:-1], changes + [changes[-1]], list(reversed(changes))]
        changed = copy.deepcopy(changes); changed[0]['before_blob'] = '0' * 40; variants.append(changed)
        changed = copy.deepcopy(changes); changed[0]['hunks'][0]['before'] += ' '; variants.append(changed)
        for rows in variants:
            value = copy.deepcopy(PATHFIX_SELECTION); value['xctestrun_path_repair']['payload_changes'] = rows
            with mock.patch.object(runner, 'PATHFIX_LAYER', value['xctestrun_path_repair']), \
                 mock.patch.object(runner, 'PATHFIX_SELECTION_SHA256', runner.hashlib.sha256(runner.encode(value).encode()).hexdigest()), \
                 self.assertRaises(ValueError):
                runner.pathfix_predecessor_selection(value)

CASEFOLD183_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity', 'NativeC2afBoundary.test_original83_complete_method_sources_are_unchanged', 'NativeC2afBoundary.test_new14_old15_history34_history19_and_original65_remain_separate', 'NativeC2afBoundary.test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources', 'NativeC2afBoundary.test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted', 'NativeC2afBoundary.test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape', 'NativeC2afBoundary.test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation', 'NativeC2afBoundary.test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse', 'NativeC2afBoundary.test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks', 'NativeC2afBoundary.test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks', 'NativeC2afBoundary.test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory', 'NativeC2afBoundary.test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer', 'NativeC2afBoundary.test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport', 'FixedPublicRepairRead.test_present_exact_3393_never_fetches', 'FixedPublicRepairRead.test_missing_3393_uses_only_separate_fixed_public_bounded_fetch', 'FixedPublicRepairRead.test_3393_network_failures_and_credential_configuration_refuse_without_retry', 'FixedPublicRepairRead.test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail', 'PortableDiagnosticBoundary.test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings', 'PortableDiagnosticBoundary.test_exact_f04_selection_source_and_four_path_layer_are_mandatory', 'PortableDiagnosticBoundary.test_all_four_actual_current_files_and_both_tree_authorities_are_strict', 'PortableDiagnosticBoundary.test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk', 'PortableDiagnosticBoundary.test_new4_and_published14_15_34_19_scope_cannot_be_relabelled', 'PortableDiagnosticBoundary.test_portable_receipt_requires_new_identity_before_original65_checks', 'FixedPublicNativeRead.test_present_c2af_never_fetches', 'FixedPublicNativeRead.test_missing_c2af_is_one_exact_bounded_public_read', 'FixedPublicNativeRead.test_bad_c2af_identity_config_timeout_and_parent_fail_closed', 'DescriptionRepairBoundary.test_complete_original108_methods_and_decorators_are_byte_identical', 'DescriptionRepairBoundary.test_original108_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'DescriptionRepairBoundary.test_new11_old4_native14_15_34_19_and_original65_stay_separate', 'DescriptionRepairBoundary.test_all_eight_current_payloads_restore_exact_complete_7b_bytes', 'DescriptionRepairBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'DescriptionRepairBoundary.test_each_of_eleven_current_files_rejects_missing_old_and_same_stat_bytes', 'DescriptionRepairBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'DescriptionRepairBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'DescriptionRepairBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'DescriptionRepairBoundary.test_every_before_and_current_tree_requires_all_eleven_exact_modes_blobs_and_types', 'DescriptionRepairBoundary.test_new11_scope_authenticates_old4_native14_and_all_older_domains', 'DescriptionRepairBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'DescriptionRepairBoundary.test_description_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'FixedPublicPortableRead.test_present_exact_f04_never_fetches_or_reads_network_configuration', 'FixedPublicPortableRead.test_missing_f04_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPortableRead.test_f04_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPortableRead.test_f04_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPortableRead.test_existing_or_fetched_f04_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPortableRead.test_fixed_f04_public_object_identity_cannot_be_generalized', 'SocialActorBoundary.test_complete_original127_methods_and_decorators_are_byte_identical', 'SocialActorBoundary.test_original127_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'SocialActorBoundary.test_new15_old11_old4_native14_15_34_19_and_original65_stay_separate', 'SocialActorBoundary.test_all_twelve_current_payloads_restore_exact_complete_42_bytes', 'SocialActorBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'SocialActorBoundary.test_each_of_fifteen_current_files_rejects_missing_old_and_same_stat_bytes', 'SocialActorBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'SocialActorBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'SocialActorBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'SocialActorBoundary.test_every_before_and_current_tree_requires_all_fifteen_exact_modes_blobs_and_types', 'SocialActorBoundary.test_new15_scope_authenticates_old11_old4_native14_and_all_older_domains', 'SocialActorBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'SocialActorBoundary.test_social_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'SocialActorBoundary.test_actor_leaf_is_only_initializer_annotation_and_equatable_identity_bytes_are_unchanged', 'SocialActorBoundary.test_merchant_single_test_leaf_matches_reviewed_complete_after_and_exact42_before', 'SocialActorBoundary.test_historical_inputs_copy_bytes_without_aliasing_any_current_checkout_file', 'SocialActorBoundary.test_new_performance_control_cannot_claim_any_historical_predecessor', 'FixedPublicDescriptionRead.test_present_exact_7b_never_fetches_or_reads_network_configuration', 'FixedPublicDescriptionRead.test_missing_7b_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicDescriptionRead.test_7b_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicDescriptionRead.test_7b_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicDescriptionRead.test_existing_or_fetched_7b_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicDescriptionRead.test_fixed_7b_public_object_identity_cannot_be_generalized', 'PathTemplateDiagnosticBoundary.test_original150_complete_method_bytes_and_decorators_are_unchanged', 'PathTemplateDiagnosticBoundary.test_original150_source_identity_rejects_body_comment_missing_and_duplicate_method', 'PathTemplateDiagnosticBoundary.test_complete_bb5_predecessor_json_and_test_bytes_are_fixed', 'PathTemplateDiagnosticBoundary.test_all_three_current_raw_files_reject_missing_old_same_size_mtime_and_links_after_warm', 'PathTemplateDiagnosticBoundary.test_noncanonical_selection_bytes_and_unknown_or_missing_layer_are_rejected', 'PathTemplateDiagnosticBoundary.test_missing_foreign_source_never_falls_back_to_loaded_healthy_root', 'PathTemplateDiagnosticBoundary.test_parent_directory_symlink_is_rejected_even_for_byte_identical_inputs', 'PathTemplateDiagnosticBoundary.test_historical_fixture_has_no_hardlink_into_real_current_source', 'PathTemplateDiagnosticBoundary.test_coherent_outer_repin_cannot_change_before_blobs_or_any_historical_selection_byte', 'PathTemplateDiagnosticBoundary.test_exact_new3_scope_preserves_all_published_fifteen_and_older_layers', 'PathTemplateDiagnosticBoundary.test_scope_rejects_new_parent_merge_mode_missing_extra_and_every_old_scope', 'PathTemplateDiagnosticBoundary.test_receipt_requires_pathfix_and_every_old_identity_and_all65_real_results', 'XctestrunPathTemplateTests.test_plain_and_double_underscore_product_root_aliases', 'XctestrunPathTemplateTests.test_literal_token_product_roots_are_not_reexpanded', 'XctestrunPathTemplateTests.test_double_underscore_product_children_and_absolute_paths', 'XctestrunPathTemplateTests.test_nested_host_tokens_preserve_literal_physical_root_names', 'XctestrunPathTemplateTests.test_unknown_template_tokens_reject_existing_literal_paths', 'XctestrunPathTemplateTests.test_missing_empty_and_recursive_host_tokens_reject', 'XctestrunPathTemplateTests.test_relative_and_missing_product_fields_reject', 'XctestrunPathTemplateTests.test_parent_and_absolute_sibling_escapes_reject', 'XctestrunPathTemplateTests.test_product_links_stay_inside_root_and_run_links_reject', 'XctestrunPathTemplateTests.test_multiple_runs_extra_targets_and_no_match_reject', 'XctestrunPathTemplateTests.test_non_token_double_underscore_names_remain_literal', 'FixedPublicSocialRead.test_present_exact_42_never_fetches_or_reads_network_configuration', 'FixedPublicSocialRead.test_missing_42_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicSocialRead.test_42_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicSocialRead.test_42_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicSocialRead.test_existing_or_fetched_42_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicSocialRead.test_fixed_42_public_object_identity_cannot_be_generalized', 'AlbumGetterActorBoundary.test_all179_previously_reviewed_method_bytes_remain_exact', 'AlbumGetterActorBoundary.test_exact_eight_payloads_restore_bb5_and_keep_all_other_files_out', 'AlbumGetterActorBoundary.test_only_actor_annotation_changes_and_all_nine_swift_methods_stay_intact', 'AlbumGetterActorBoundary.test_payload_rows_cannot_omit_duplicate_reorder_or_coherently_replace_preimages')
CASEFOLD183_SOURCE_SHA256 = '297bd7f3787356f47b92d2d7a98a7ce20223a6049b652effa6d578b187a4f58d'
def casefold_original183_blocks(raw):
    lines = raw.splitlines(True)
    found = {}
    for cls in ast.parse(raw).body:
        if not isinstance(cls, ast.ClassDef): continue
        for node in cls.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
            key = cls.name + '.' + node.name
            if key not in CASEFOLD183_IDENTITIES: continue
            if key in found: raise ValueError('Duplicate original183 method')
            first = min([node.lineno] + [d.lineno for d in node.decorator_list])
            found[key] = b''.join(lines[first - 1:node.end_lineno]).decode()
    if (len(found) != 183 or set(found) != set(CASEFOLD183_IDENTITIES)
            or runner.hashlib.sha256(runner.encode(found).encode()).hexdigest() != CASEFOLD183_SOURCE_SHA256):
        raise ValueError('Changed complete original183 method bytes')
    return found


class CasefoldFixtureBoundary(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='casefold-current-three-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for path in runner.CASEFOLD_PATHS:
            output = root / path
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes((CASEFOLD_SOURCE / path).read_bytes())
        return root

    def test_all183_complete_method_bytes_decorators_and_comments_remain_unchanged(self):
        old = runner.casefold_predecessor_sources(CASEFOLD_SELECTION, CASEFOLD_SOURCE)[runner.CASEFOLD_PATHS[2]]
        current = (CASEFOLD_SOURCE / runner.CASEFOLD_PATHS[2]).read_bytes()
        self.assertEqual(casefold_original183_blocks(old), casefold_original183_blocks(current))
        first = next(iter(casefold_original183_blocks(old).values())).encode()
        for changed in (current.replace(first, b'', 1), current.replace(first, first + b'\n' + first, 1),
                        current.replace(first, first.replace(b'\n', b'\n        # changed source\n', 1), 1)):
            with self.assertRaises(ValueError): casefold_original183_blocks(changed)

    def test_actual_identical_and_case_variant_names_have_independent_parents(self):
        fixture = XctestrunPathTemplateTests()
        fixture.setUp(); self.addCleanup(fixture.doCleanups)
        names = ('name__unfinished', 'name__UNFINISHED', 'double__underscore__path', 'name__unfinished')
        roots = [fixture._products(name) for name in names]
        self.assertEqual([p.name for p in roots], list(names))
        self.assertEqual(len({str(p.parent).casefold() for p in roots}), len(names))
        for path in roots:
            self.assertTrue(path.is_dir())
            self.assertTrue(path.resolve().is_relative_to(fixture.root.resolve()))
        for path in roots[:3]:
            run = fixture._write_run(path, fixture._plain(path, path.name))
            self.assertEqual(runner.select_xctestrun(path, 'QuestifyUITests'), run.resolve())

    def test_simulated_casefold_directory_collision_rejects_old_layout_not_isolated_helper(self):
        """Explicit casefold simulation over real files; not a claim about host FS semantics."""
        fixture = XctestrunPathTemplateTests()
        fixture.setUp(); self.addCleanup(fixture.doCleanups)
        original_mkdir = Path.mkdir
        def casefold_mkdir(path, *args, **kwargs):
            if path.parent.is_dir():
                for sibling in path.parent.iterdir():
                    if sibling.name.casefold() == path.name.casefold() and sibling.name != path.name:
                        raise FileExistsError('Simulated case-insensitive directory alias: ' + str(path))
            return original_mkdir(path, *args, **kwargs)
        old = fixture.root / 'old-layout'; old.mkdir()
        with mock.patch.object(Path, 'mkdir', casefold_mkdir):
            (old / 'name__unfinished').mkdir()
            with self.assertRaises(FileExistsError): (old / 'name__UNFINISHED').mkdir()
            fresh = [fixture._products(name) for name in ('name__unfinished', 'name__UNFINISHED', 'double__underscore__path')]
            self.assertEqual(len({str(p.parent).casefold() for p in fresh}), 3)
            for path in fresh:
                run = fixture._write_run(path, fixture._plain(path, path.name))
                self.assertEqual(runner.select_xctestrun(path, 'QuestifyUITests'), run.resolve())
        # A broken allocator that reuses one parent reproduces the same failure.
        coalesced = fixture.root / 'coalesced'; coalesced.mkdir()
        with mock.patch.object(tempfile, 'mkdtemp', return_value=str(coalesced)), mock.patch.object(Path, 'mkdir', casefold_mkdir):
            fixture._products('name__unfinished')
            with self.assertRaises(FileExistsError): fixture._products('name__UNFINISHED')

    def test_selector_complete_function_and_original_literal_cases_remain_fixed(self):
        raw = (CASEFOLD_SOURCE / runner.CASEFOLD_PATHS[0]).read_bytes()
        node = next(n for n in ast.parse(raw).body if isinstance(n, ast.FunctionDef) and n.name == 'select_xctestrun')
        source = b''.join(raw.splitlines(True)[node.lineno - 1:node.end_lineno])
        self.assertEqual(runner.hashlib.sha256(source).hexdigest(), '2690b28488e15a9887d624e7aae6e28dccc4a2e748a16a45479cda57b68dc361')
        method = casefold_original183_blocks((CASEFOLD_SOURCE / runner.CASEFOLD_PATHS[2]).read_bytes())[
            'XctestrunPathTemplateTests.test_non_token_double_underscore_names_remain_literal']
        self.assertIn("('name__unfinished', 'name__UNFINISHED', 'double__underscore__path')", method)
        self.assertIn("self.assertEqual(runner.select_xctestrun(products, 'QuestifyUITests'), run.resolve())", method)

    def test_current_three_raw_missing_old_same_stat_symlink_and_foreign_root_rejected(self):
        root = self.fixture()
        runner.casefold_current_inputs(CASEFOLD_SELECTION, root)
        old = runner.casefold_predecessor_sources(CASEFOLD_SELECTION, root)
        for relative in runner.CASEFOLD_PATHS:
            path = root / relative; raw = path.read_bytes(); stat = path.stat()
            path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:]); os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            with self.subTest(path=relative, mode='same-stat'), self.assertRaises(ValueError):
                runner.casefold_current_inputs(CASEFOLD_SELECTION, root)
            path.unlink()
            with self.subTest(path=relative, mode='missing'), self.assertRaises((ValueError, OSError)):
                runner.casefold_current_inputs(CASEFOLD_SELECTION, root)
            path.symlink_to(CASEFOLD_SOURCE / relative)
            with self.subTest(path=relative, mode='symlink'), self.assertRaises(ValueError):
                runner.casefold_current_inputs(CASEFOLD_SELECTION, root)
            path.unlink(); path.write_bytes(raw)
            if relative != runner.CASEFOLD_PATHS[0]:
                path.write_bytes(old[relative])
                with self.subTest(path=relative, mode='old'), self.assertRaises(ValueError):
                    runner.casefold_current_inputs(CASEFOLD_SELECTION, root)
                path.write_bytes(raw)
        with tempfile.TemporaryDirectory() as missing:
            with self.assertRaises((ValueError, OSError)):
                runner.validate_casefold_selection(CASEFOLD_SELECTION, Path(missing))

    def test_exact_raw_json_and_coherent_before_repin_cannot_forge_predecessor(self):
        root = self.fixture(); path = root / runner.CASEFOLD_PATHS[1]; raw = path.read_bytes()
        for variant in (raw + b'\n', raw.replace(b'\n', b'\r\n'), json.dumps(CASEFOLD_SELECTION).encode()):
            path.write_bytes(variant)
            with self.assertRaises(ValueError): runner.casefold_current_inputs(CASEFOLD_SELECTION, root)
        for mode in ('before', 'old-field'):
            changed = copy.deepcopy(CASEFOLD_SELECTION)
            if mode == 'before': changed['casefold_fixture_repair']['diagnostic_before_blobs'][runner.CASEFOLD_PATHS[0]] = '0' * 40
            else: changed['unexpected_historical_key'] = True
            encoded = (json.dumps(changed, indent=2, ensure_ascii=True) + '\n').encode(); path.write_bytes(encoded)
            with mock.patch.object(runner, 'CASEFOLD_LAYER', changed['casefold_fixture_repair']), \
                 mock.patch.object(runner, 'CASEFOLD_SELECTION_SHA256', runner.hashlib.sha256(runner.encode(changed).encode()).hexdigest()), \
                 mock.patch.object(runner, 'CASEFOLD_SELECTION_RAW_SHA256', runner.hashlib.sha256(encoded).hexdigest()), self.assertRaises(ValueError):
                runner.casefold_current_inputs(changed, root)

    def test_published54_complete_before_images_and_old_domain_do_not_admit_new_layer(self):
        incoming = runner.casefold_predecessor_sources(CASEFOLD_SELECTION, CASEFOLD_SOURCE)
        for path in runner.CASEFOLD_PATHS[1:]:
            self.assertEqual(runner.blob_id(incoming[path]), runner.CASEFOLD_BEFORE_BLOBS[path])
            self.assertEqual(incoming[path], (PATHFIX_SOURCE / path).read_bytes())
        self.assertEqual(runner.validate_casefold_selection(CASEFOLD_SELECTION, CASEFOLD_SOURCE), CASEFOLD_SELECTION)
        with self.assertRaises(ValueError): runner.validate_pathfix_selection(CASEFOLD_SELECTION, CASEFOLD_SOURCE)
        with self.assertRaises(ValueError): runner.validate_casefold_selection(PATHFIX_SELECTION, PATHFIX_SOURCE)
        self.assertEqual(CASEFOLD_SELECTION['groups'], PATHFIX_SELECTION['groups'])
        self.assertEqual(len(runner.CASEFOLD_PATHS), 3)

    def test_bounded_published54_fixture_never_hardlinks_current_sources(self):
        for relative in (*runner.CASEFOLD_PATHS, 'App/ProjectThoughtDefinitionsEditor.swift', 'Tests/AppUnitTests/ProjectAlbumImageAuthorTests.swift'):
            current = CASEFOLD_SOURCE / relative; historical = PATHFIX_SOURCE / relative
            self.assertFalse(os.path.samefile(current, historical))
            self.assertEqual(current.stat().st_nlink, 1)
            self.assertEqual(historical.stat().st_nlink, 1)

    def test_receipt_requires_new_identity_every_old_layer_and_all65_actual_methods(self):
        receipt, expected = ReceiptIdentity().receipt()
        receipt.update(native_base_commit=runner.NATIVE_BASE_COMMIT, native_base_tree=runner.NATIVE_BASE_TREE,
                       native_selection=runner.NATIVE_NAME, portable_base_commit=runner.PORTABLE_BASE_COMMIT,
                       portable_base_tree=runner.PORTABLE_BASE_TREE, portable_selection=runner.PORTABLE_LAYER['name'],
                       description_base_commit=runner.DESCRIPTION_BASE_COMMIT, description_base_tree=runner.DESCRIPTION_BASE_TREE,
                       description_selection=runner.DESCRIPTION_LAYER['name'], social_base_commit=runner.SOCIAL_BASE_COMMIT,
                       social_base_tree=runner.SOCIAL_BASE_TREE, social_selection=runner.SOCIAL_LAYER['name'],
                       pathfix_base_commit=runner.PATHFIX_BASE_COMMIT, pathfix_base_tree=runner.PATHFIX_BASE_TREE,
                       pathfix_selection=runner.PATHFIX_NAME)
        with self.assertRaises(ValueError): runner.validate_casefold_pass_receipt(receipt, expected, CASEFOLD_SELECTION)
        receipt.update(casefold_base_commit=runner.CASEFOLD_BASE_COMMIT, casefold_base_tree=runner.CASEFOLD_BASE_TREE,
                       casefold_selection=runner.CASEFOLD_NAME)
        runner.validate_casefold_pass_receipt(receipt, expected, CASEFOLD_SELECTION)
        for key in ('casefold_base_commit', 'casefold_base_tree', 'casefold_selection', 'pathfix_base_commit',
                    'social_base_commit', 'description_base_commit', 'portable_base_commit', 'native_base_commit'):
            changed = copy.deepcopy(receipt); changed[key] = 'wrong'
            with self.subTest(key=key), self.assertRaises(ValueError):
                runner.validate_casefold_pass_receipt(changed, expected, CASEFOLD_SELECTION)
        changed = copy.deepcopy(receipt); changed['groups']['core']['actual'] = []
        with self.assertRaises(ValueError): runner.validate_casefold_pass_receipt(changed, expected, CASEFOLD_SELECTION)


class FixedPublicPathfixRead(unittest.TestCase):
    """Mocked public-read boundaries only; these tests perform no network fetch."""
    def headers(self):
        return 'tree ' + runner.PATHFIX_BASE_TREE + '\nparent ' + runner.SOCIAL_BASE_COMMIT + '\n\nSynthetic bb5 metadata'

    def present(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        if command == ['git', 'cat-file', '-p', runner.PATHFIX_BASE_COMMIT]: return self.headers()
        raise AssertionError(command)

    def missing(self, command, root):
        if command[1:3] == ['cat-file', '-e']: raise ValueError('Synthetic missing fixed bb5 object')
        return self.present(command, root)

    def test_present_exact_bb5_never_fetches_or_reads_network_configuration(self):
        with mock.patch.object(runner, 'checked', side_effect=self.present), mock.patch.object(runner, 'execute') as execute:
            runner.ensure_pathfix_commit(CASEFOLD_SOURCE)
        execute.assert_not_called()

    def test_missing_bb5_uses_one_exact_bounded_noninteractive_public_read_without_credentials(self):
        environment = {'GITHUB_TOKEN': 'synthetic-not-a-secret', 'GH_TOKEN': 'synthetic-not-a-secret',
                       'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'http.extraHeader',
                       'GIT_CONFIG_VALUE_0': 'synthetic-not-a-secret', 'GIT_SSH_COMMAND': 'unexpected',
                       'HTTP_PROXY': 'http://example.invalid', 'HTTPS_PROXY': 'http://example.invalid'}
        with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', side_effect=self.missing), \
             mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute:
            runner.ensure_pathfix_commit(CASEFOLD_SOURCE)
        self.assertEqual(execute.call_count, 2)
        config, fetch = execute.call_args_list
        self.assertEqual(config.args[0], ['git', 'config', '--local', '--includes', '--name-only', '--list'])
        self.assertEqual(config.args[2], 10)
        self.assertEqual(fetch.args[0], ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                                       '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                                       '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                                       'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                                       'https://github.com/liboyang42-cpu/chengyin-ios.git',
                                       'bb5d22fdd7c14d3fa747c4048babb8ebd6e659db'])
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

    def test_bb5_credential_redirect_include_and_auth_configuration_fail_before_fetch(self):
        keys = ('credential.helper', 'credential.https://github.com.username', 'http.extraheader',
                'http.https://github.com/.extraheader', 'http.proxy', 'url.ssh://example.invalid.insteadof',
                'include.path', 'includeif.gitdir:work.path', 'core.askpass', 'extensions.worktreeconfig')
        for key in keys:
            with self.subTest(key=key), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', return_value=(0, (key + '\n').encode())) as execute, self.assertRaises(ValueError):
                runner.ensure_pathfix_commit(CASEFOLD_SOURCE)
            self.assertEqual(execute.call_count, 1)

    def test_bb5_unreadable_config_offline_and_timeout_fail_closed_without_retry(self):
        for mode in ('config', 'offline', 'timeout'):
            outputs = [(1, b'')] if mode == 'config' else [(0, b'core.bare\n'), (124 if mode == 'timeout' else 1, b'')]
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', side_effect=outputs) as execute, self.assertRaises(ValueError):
                runner.ensure_pathfix_commit(CASEFOLD_SOURCE)
            self.assertEqual(execute.call_count, 1 if mode == 'config' else 2)

    def test_existing_or_fetched_bb5_wrong_tree_parent_merge_or_missing_headers_fail(self):
        bad_headers = (self.headers().replace(runner.PATHFIX_BASE_TREE, '0' * 40),
                       self.headers().replace(runner.SOCIAL_BASE_COMMIT, runner.BASE_COMMIT),
                       self.headers().replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n'),
                       self.headers().replace('tree ' + runner.PATHFIX_BASE_TREE + '\n', ''),
                       self.headers().replace('parent ' + runner.SOCIAL_BASE_COMMIT + '\n', ''),
                       self.headers().replace('\nparent ', '\ntree ' + runner.PATHFIX_BASE_TREE + '\nparent ', 1))
        for existing in (True, False):
            for bad in bad_headers:
                def read(command, root):
                    if command[1:3] == ['cat-file', '-e']:
                        if existing: return ''
                        raise ValueError('Synthetic missing bb5')
                    return bad
                with self.subTest(existing=existing, headers=bad), mock.patch.object(runner, 'checked', side_effect=read), \
                     mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute, self.assertRaises(ValueError):
                    runner.ensure_pathfix_commit(CASEFOLD_SOURCE)
                self.assertEqual(execute.call_count, 0 if existing else 2)

    def test_fixed_bb5_public_object_identity_cannot_be_generalized(self):
        for key in ('PATHFIX_BASE_COMMIT', 'PATHFIX_BASE_TREE'):
            with self.subTest(key=key), mock.patch.object(runner, key, '0' * 40), \
                 mock.patch.object(runner, 'checked') as read, mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_pathfix_commit(CASEFOLD_SOURCE)
            read.assert_not_called(); execute.assert_not_called()



BYTEPERF198_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity', 'NativeC2afBoundary.test_original83_complete_method_sources_are_unchanged', 'NativeC2afBoundary.test_new14_old15_history34_history19_and_original65_remain_separate', 'NativeC2afBoundary.test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources', 'NativeC2afBoundary.test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted', 'NativeC2afBoundary.test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape', 'NativeC2afBoundary.test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation', 'NativeC2afBoundary.test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse', 'NativeC2afBoundary.test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks', 'NativeC2afBoundary.test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks', 'NativeC2afBoundary.test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory', 'NativeC2afBoundary.test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer', 'NativeC2afBoundary.test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport', 'FixedPublicRepairRead.test_present_exact_3393_never_fetches', 'FixedPublicRepairRead.test_missing_3393_uses_only_separate_fixed_public_bounded_fetch', 'FixedPublicRepairRead.test_3393_network_failures_and_credential_configuration_refuse_without_retry', 'FixedPublicRepairRead.test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail', 'PortableDiagnosticBoundary.test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings', 'PortableDiagnosticBoundary.test_exact_f04_selection_source_and_four_path_layer_are_mandatory', 'PortableDiagnosticBoundary.test_all_four_actual_current_files_and_both_tree_authorities_are_strict', 'PortableDiagnosticBoundary.test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk', 'PortableDiagnosticBoundary.test_new4_and_published14_15_34_19_scope_cannot_be_relabelled', 'PortableDiagnosticBoundary.test_portable_receipt_requires_new_identity_before_original65_checks', 'FixedPublicNativeRead.test_present_c2af_never_fetches', 'FixedPublicNativeRead.test_missing_c2af_is_one_exact_bounded_public_read', 'FixedPublicNativeRead.test_bad_c2af_identity_config_timeout_and_parent_fail_closed', 'DescriptionRepairBoundary.test_complete_original108_methods_and_decorators_are_byte_identical', 'DescriptionRepairBoundary.test_original108_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'DescriptionRepairBoundary.test_new11_old4_native14_15_34_19_and_original65_stay_separate', 'DescriptionRepairBoundary.test_all_eight_current_payloads_restore_exact_complete_7b_bytes', 'DescriptionRepairBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'DescriptionRepairBoundary.test_each_of_eleven_current_files_rejects_missing_old_and_same_stat_bytes', 'DescriptionRepairBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'DescriptionRepairBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'DescriptionRepairBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'DescriptionRepairBoundary.test_every_before_and_current_tree_requires_all_eleven_exact_modes_blobs_and_types', 'DescriptionRepairBoundary.test_new11_scope_authenticates_old4_native14_and_all_older_domains', 'DescriptionRepairBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'DescriptionRepairBoundary.test_description_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'FixedPublicPortableRead.test_present_exact_f04_never_fetches_or_reads_network_configuration', 'FixedPublicPortableRead.test_missing_f04_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPortableRead.test_f04_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPortableRead.test_f04_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPortableRead.test_existing_or_fetched_f04_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPortableRead.test_fixed_f04_public_object_identity_cannot_be_generalized', 'SocialActorBoundary.test_complete_original127_methods_and_decorators_are_byte_identical', 'SocialActorBoundary.test_original127_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'SocialActorBoundary.test_new15_old11_old4_native14_15_34_19_and_original65_stay_separate', 'SocialActorBoundary.test_all_twelve_current_payloads_restore_exact_complete_42_bytes', 'SocialActorBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'SocialActorBoundary.test_each_of_fifteen_current_files_rejects_missing_old_and_same_stat_bytes', 'SocialActorBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'SocialActorBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'SocialActorBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'SocialActorBoundary.test_every_before_and_current_tree_requires_all_fifteen_exact_modes_blobs_and_types', 'SocialActorBoundary.test_new15_scope_authenticates_old11_old4_native14_and_all_older_domains', 'SocialActorBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'SocialActorBoundary.test_social_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'SocialActorBoundary.test_actor_leaf_is_only_initializer_annotation_and_equatable_identity_bytes_are_unchanged', 'SocialActorBoundary.test_merchant_single_test_leaf_matches_reviewed_complete_after_and_exact42_before', 'SocialActorBoundary.test_historical_inputs_copy_bytes_without_aliasing_any_current_checkout_file', 'SocialActorBoundary.test_new_performance_control_cannot_claim_any_historical_predecessor', 'FixedPublicDescriptionRead.test_present_exact_7b_never_fetches_or_reads_network_configuration', 'FixedPublicDescriptionRead.test_missing_7b_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicDescriptionRead.test_7b_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicDescriptionRead.test_7b_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicDescriptionRead.test_existing_or_fetched_7b_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicDescriptionRead.test_fixed_7b_public_object_identity_cannot_be_generalized', 'PathTemplateDiagnosticBoundary.test_original150_complete_method_bytes_and_decorators_are_unchanged', 'PathTemplateDiagnosticBoundary.test_original150_source_identity_rejects_body_comment_missing_and_duplicate_method', 'PathTemplateDiagnosticBoundary.test_complete_bb5_predecessor_json_and_test_bytes_are_fixed', 'PathTemplateDiagnosticBoundary.test_all_three_current_raw_files_reject_missing_old_same_size_mtime_and_links_after_warm', 'PathTemplateDiagnosticBoundary.test_noncanonical_selection_bytes_and_unknown_or_missing_layer_are_rejected', 'PathTemplateDiagnosticBoundary.test_missing_foreign_source_never_falls_back_to_loaded_healthy_root', 'PathTemplateDiagnosticBoundary.test_parent_directory_symlink_is_rejected_even_for_byte_identical_inputs', 'PathTemplateDiagnosticBoundary.test_historical_fixture_has_no_hardlink_into_real_current_source', 'PathTemplateDiagnosticBoundary.test_coherent_outer_repin_cannot_change_before_blobs_or_any_historical_selection_byte', 'PathTemplateDiagnosticBoundary.test_exact_new3_scope_preserves_all_published_fifteen_and_older_layers', 'PathTemplateDiagnosticBoundary.test_scope_rejects_new_parent_merge_mode_missing_extra_and_every_old_scope', 'PathTemplateDiagnosticBoundary.test_receipt_requires_pathfix_and_every_old_identity_and_all65_real_results', 'XctestrunPathTemplateTests.test_plain_and_double_underscore_product_root_aliases', 'XctestrunPathTemplateTests.test_literal_token_product_roots_are_not_reexpanded', 'XctestrunPathTemplateTests.test_double_underscore_product_children_and_absolute_paths', 'XctestrunPathTemplateTests.test_nested_host_tokens_preserve_literal_physical_root_names', 'XctestrunPathTemplateTests.test_unknown_template_tokens_reject_existing_literal_paths', 'XctestrunPathTemplateTests.test_missing_empty_and_recursive_host_tokens_reject', 'XctestrunPathTemplateTests.test_relative_and_missing_product_fields_reject', 'XctestrunPathTemplateTests.test_parent_and_absolute_sibling_escapes_reject', 'XctestrunPathTemplateTests.test_product_links_stay_inside_root_and_run_links_reject', 'XctestrunPathTemplateTests.test_multiple_runs_extra_targets_and_no_match_reject', 'XctestrunPathTemplateTests.test_non_token_double_underscore_names_remain_literal', 'FixedPublicSocialRead.test_present_exact_42_never_fetches_or_reads_network_configuration', 'FixedPublicSocialRead.test_missing_42_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicSocialRead.test_42_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicSocialRead.test_42_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicSocialRead.test_existing_or_fetched_42_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicSocialRead.test_fixed_42_public_object_identity_cannot_be_generalized', 'AlbumGetterActorBoundary.test_all179_previously_reviewed_method_bytes_remain_exact', 'AlbumGetterActorBoundary.test_exact_eight_payloads_restore_bb5_and_keep_all_other_files_out', 'AlbumGetterActorBoundary.test_only_actor_annotation_changes_and_all_nine_swift_methods_stay_intact', 'AlbumGetterActorBoundary.test_payload_rows_cannot_omit_duplicate_reorder_or_coherently_replace_preimages', 'CasefoldFixtureBoundary.test_all183_complete_method_bytes_decorators_and_comments_remain_unchanged', 'CasefoldFixtureBoundary.test_actual_identical_and_case_variant_names_have_independent_parents', 'CasefoldFixtureBoundary.test_simulated_casefold_directory_collision_rejects_old_layout_not_isolated_helper', 'CasefoldFixtureBoundary.test_selector_complete_function_and_original_literal_cases_remain_fixed', 'CasefoldFixtureBoundary.test_current_three_raw_missing_old_same_stat_symlink_and_foreign_root_rejected', 'CasefoldFixtureBoundary.test_exact_raw_json_and_coherent_before_repin_cannot_forge_predecessor', 'CasefoldFixtureBoundary.test_published54_complete_before_images_and_old_domain_do_not_admit_new_layer', 'CasefoldFixtureBoundary.test_bounded_published54_fixture_never_hardlinks_current_sources', 'CasefoldFixtureBoundary.test_receipt_requires_new_identity_every_old_layer_and_all65_actual_methods', 'FixedPublicPathfixRead.test_present_exact_bb5_never_fetches_or_reads_network_configuration', 'FixedPublicPathfixRead.test_missing_bb5_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPathfixRead.test_bb5_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPathfixRead.test_bb5_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPathfixRead.test_existing_or_fetched_bb5_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPathfixRead.test_fixed_bb5_public_object_identity_cannot_be_generalized')
BYTEPERF198_SOURCE_SHA256 = '8ab44752fb92d855c1935b34b324171da3a806d16c1987d394b8be940e073570'
def byteperf_original198_blocks(raw):
    lines = raw.splitlines(True)
    found = {}
    for cls in ast.parse(raw).body:
        if not isinstance(cls, ast.ClassDef): continue
        for node in cls.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)): continue
            key = cls.name + '.' + node.name
            if key not in BYTEPERF198_IDENTITIES: continue
            if key in found: raise ValueError('Duplicate original198 method')
            first = min([node.lineno] + [d.lineno for d in node.decorator_list])
            found[key] = b''.join(lines[first - 1:node.end_lineno]).decode()
    if (len(found) != 198 or set(found) != set(BYTEPERF198_IDENTITIES)
            or runner.hashlib.sha256(runner.encode(found).encode()).hexdigest() != BYTEPERF198_SOURCE_SHA256):
        raise ValueError('Changed complete original198 method bytes')
    return found


class BoundedByteTransformBoundary(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='byteperf-current-nine-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for relative in runner.BYTEPERF_PATHS:
            path = root / relative; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((BYTEPERF_SOURCE / relative).read_bytes())
        return root

    def test_complete_original198_methods_are_preserved_without_weakened_assertions(self):
        old = runner.byteperf_predecessor_sources(BYTEPERF_SELECTION, BYTEPERF_SOURCE)[runner.CASEFOLD_PATHS[2]]
        raw = (BYTEPERF_SOURCE / runner.CASEFOLD_PATHS[2]).read_bytes()
        self.assertEqual(byteperf_original198_blocks(raw), byteperf_original198_blocks(old))
        first = next(iter(byteperf_original198_blocks(old).values())).encode()
        for changed in (raw.replace(first, b'', 1), raw.replace(first, first + b'\n' + first, 1),
                        raw.replace(first, first.replace(b'\n', b'\n        # altered assertion body\n', 1), 1)):
            with self.assertRaises(ValueError): byteperf_original198_blocks(changed)

    def test_warm_boundaries_reject_each_current_raw_same_size_mtime_missing_and_symlink(self):
        root = self.fixture()
        old = runner.byteperf_predecessor_sources(BYTEPERF_SELECTION, root)
        for relative in runner.BYTEPERF_PATHS:
            path = root / relative; raw = path.read_bytes(); stat = path.stat()
            path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:]); os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            for operation in (runner.byteperf_current_inputs, runner.byteperf_predecessor_sources):
                with self.subTest(path=relative, operation=operation.__name__), self.assertRaises(ValueError):
                    operation(BYTEPERF_SELECTION, root)
            path.unlink()
            with self.assertRaises((ValueError, OSError)): runner.byteperf_current_inputs(BYTEPERF_SELECTION, root)
            path.symlink_to(BYTEPERF_SOURCE / relative)
            with self.assertRaises(ValueError): runner.byteperf_current_inputs(BYTEPERF_SELECTION, root)
            path.unlink(); path.write_bytes(raw)
            if relative in old and relative != runner.CASEFOLD_PATHS[0]:
                path.write_bytes(old[relative])
                with self.assertRaises(ValueError): runner.byteperf_current_inputs(BYTEPERF_SELECTION, root)
                path.write_bytes(raw)
        runner.byteperf_current_inputs(BYTEPERF_SELECTION, root)

    def test_all_five_source_inverses_restore_complete_published_c3a_bytes(self):
        old = runner.byteperf_predecessor_sources(BYTEPERF_SELECTION, BYTEPERF_SOURCE)
        for row in runner.BYTEPERF_LAYER['payload']:
            path = row['path']
            if row['status'] == 'A':
                self.assertNotIn(path, old); self.assertIsNone(row['before_blob']); self.assertEqual(row['hunks'], [])
            else:
                self.assertEqual(runner.hashlib.sha256(old[path]).hexdigest(), row['before_sha256'])
                self.assertEqual(runner.blob_id(old[path]), row['before_blob'])
                self.assertEqual(old[path], (CASEFOLD_SOURCE / path).read_bytes())
        self.assertEqual(len(runner.BYTEPERF_PATHS), 9)
        self.assertEqual([r['status'] for r in runner.BYTEPERF_LAYER['payload']].count('A'), 1)
        self.assertEqual(BYTEPERF_SELECTION['groups'], CASEFOLD_SELECTION['groups'])
        self.assertEqual(runner.validate_byteperf_selection(BYTEPERF_SELECTION, BYTEPERF_SOURCE), BYTEPERF_SELECTION)

    def test_old_defaults_reject_new_layer_and_mixed_foreign_current_roots(self):
        for operation in (runner.validate_casefold_selection, runner.validate_pathfix_selection,
                          runner.validate_social_selection, runner.validate_native_selection):
            with self.subTest(operation=operation.__name__), self.assertRaises(ValueError):
                operation(BYTEPERF_SELECTION, BYTEPERF_SOURCE)
        with self.assertRaises(ValueError): runner.validate_byteperf_selection(CASEFOLD_SELECTION, CASEFOLD_SOURCE)
        with self.assertRaises(ValueError): runner.validate_byteperf_selection(BYTEPERF_SELECTION, CASEFOLD_SOURCE)
        root = self.fixture()
        with self.assertRaises((ValueError, OSError)): runner.validate_byteperf_selection(BYTEPERF_SELECTION, root)

    def test_exact_raw_selection_and_inverse_payload_cannot_be_coherently_rebound(self):
        root = self.fixture(); path = root / runner.CASEFOLD_PATHS[1]; raw = path.read_bytes()
        for variant in (raw + b'\n', raw.replace(b'\n', b'\r\n'), json.dumps(BYTEPERF_SELECTION).encode()):
            path.write_bytes(variant)
            with self.assertRaises(ValueError): runner.byteperf_current_inputs(BYTEPERF_SELECTION, root)
        path.write_bytes(raw)
        changed = copy.deepcopy(BYTEPERF_SELECTION)
        changed['bounded_byte_transform_repair']['payload'][0]['before_blob'] = '0' * 40
        with mock.patch.object(runner, 'BYTEPERF_LAYER', changed['bounded_byte_transform_repair']), self.assertRaises(ValueError):
            runner.byteperf_current_inputs(changed, root)
        for key in ('BYTEPERF_PRE_TEST_SHA256', 'BYTEPERF_PRE_SELECTION_SHA256', 'BYTEPERF_PAYLOAD_SHA256'):
            with self.subTest(key=key), mock.patch.object(runner, key, '0' * 64), self.assertRaises(ValueError):
                runner.byteperf_predecessor_sources(BYTEPERF_SELECTION, root)

    def test_warm_async_and_threaded_boundary_still_reads_actual_root_bytes(self):
        import asyncio
        from concurrent.futures import ThreadPoolExecutor
        root = self.fixture(); runner.byteperf_predecessor_sources(BYTEPERF_SELECTION, root)
        path = root / runner.BYTEPERF_LAYER['payload'][0]['path']; raw = path.read_bytes(); stat = path.stat()
        path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:]); os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        with ThreadPoolExecutor(max_workers=2) as executor:
            future = executor.submit(runner.byteperf_predecessor_sources, BYTEPERF_SELECTION, root)
            with self.assertRaises(ValueError): future.result()
        async def call():
            await asyncio.sleep(0)
            return runner.byteperf_current_inputs(BYTEPERF_SELECTION, root)
        with self.assertRaises(ValueError): asyncio.run(call())

    def test_bounded_physical_predecessors_share_no_inodes(self):
        for relative in (*runner.CASEFOLD_PATHS, *(r['path'] for r in runner.BYTEPERF_LAYER['payload'] if r['status'] == 'M')):
            current = BYTEPERF_SOURCE / relative; historical = CASEFOLD_SOURCE / relative
            self.assertFalse(os.path.samefile(current, historical))
            self.assertEqual(current.stat().st_nlink, 1); self.assertEqual(historical.stat().st_nlink, 1)

    def test_receipt_requires_all_new_and_old_identity_fields(self):
        receipt, expected = ReceiptIdentity().receipt()
        receipt.update(native_base_commit=runner.NATIVE_BASE_COMMIT, native_base_tree=runner.NATIVE_BASE_TREE,
                       native_selection=runner.NATIVE_NAME, portable_base_commit=runner.PORTABLE_BASE_COMMIT,
                       portable_base_tree=runner.PORTABLE_BASE_TREE, portable_selection=runner.PORTABLE_LAYER['name'],
                       description_base_commit=runner.DESCRIPTION_BASE_COMMIT, description_base_tree=runner.DESCRIPTION_BASE_TREE,
                       description_selection=runner.DESCRIPTION_LAYER['name'], social_base_commit=runner.SOCIAL_BASE_COMMIT,
                       social_base_tree=runner.SOCIAL_BASE_TREE, social_selection=runner.SOCIAL_LAYER['name'],
                       pathfix_base_commit=runner.PATHFIX_BASE_COMMIT, pathfix_base_tree=runner.PATHFIX_BASE_TREE,
                       pathfix_selection=runner.PATHFIX_NAME)
        receipt.update(casefold_base_commit=runner.CASEFOLD_BASE_COMMIT, casefold_base_tree=runner.CASEFOLD_BASE_TREE,
                       casefold_selection=runner.CASEFOLD_NAME)
        with self.assertRaises(ValueError): runner.validate_byteperf_pass_receipt(receipt, expected, BYTEPERF_SELECTION)
        receipt.update(byteperf_base_commit=runner.BYTEPERF_BASE_COMMIT, byteperf_base_tree=runner.BYTEPERF_BASE_TREE,
                       byteperf_selection=runner.BYTEPERF_NAME)
        runner.validate_byteperf_pass_receipt(receipt, expected, BYTEPERF_SELECTION)
        for key in ('byteperf_base_commit', 'byteperf_base_tree', 'byteperf_selection', 'casefold_base_commit',
                    'pathfix_base_commit', 'social_base_commit', 'description_base_commit',
                    'portable_base_commit', 'native_base_commit'):
            changed = copy.deepcopy(receipt); changed[key] = 'wrong'
            with self.subTest(key=key), self.assertRaises(ValueError):
                runner.validate_byteperf_pass_receipt(changed, expected, BYTEPERF_SELECTION)
        changed = copy.deepcopy(receipt); changed['groups']['core']['actual'] = []
        with self.assertRaises(ValueError): runner.validate_byteperf_pass_receipt(changed, expected, BYTEPERF_SELECTION)


class FixedPublicCasefoldRead(unittest.TestCase):
    """Mocked public-read boundaries only; these tests perform no network fetch."""
    def headers(self):
        return 'tree ' + runner.CASEFOLD_BASE_TREE + '\nparent ' + runner.PATHFIX_BASE_COMMIT + '\n\nSynthetic 54f metadata'

    def present(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        if command == ['git', 'cat-file', '-p', runner.CASEFOLD_BASE_COMMIT]: return self.headers()
        raise AssertionError(command)

    def missing(self, command, root):
        if command[1:3] == ['cat-file', '-e']: raise ValueError('Synthetic missing fixed 54f object')
        return self.present(command, root)

    def test_present_exact_54f_never_fetches_or_reads_network_configuration(self):
        with mock.patch.object(runner, 'checked', side_effect=self.present), mock.patch.object(runner, 'execute') as execute:
            runner.ensure_casefold_commit(BYTEPERF_SOURCE)
        execute.assert_not_called()

    def test_missing_54f_uses_one_exact_bounded_noninteractive_public_read_without_credentials(self):
        environment = {'GITHUB_TOKEN': 'synthetic-not-a-secret', 'GH_TOKEN': 'synthetic-not-a-secret',
                       'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'http.extraHeader',
                       'GIT_CONFIG_VALUE_0': 'synthetic-not-a-secret', 'GIT_SSH_COMMAND': 'unexpected',
                       'HTTP_PROXY': 'http://example.invalid', 'HTTPS_PROXY': 'http://example.invalid'}
        with mock.patch.dict(os.environ, environment), mock.patch.object(runner, 'checked', side_effect=self.missing), \
             mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute:
            runner.ensure_casefold_commit(BYTEPERF_SOURCE)
        self.assertEqual(execute.call_count, 2)
        config, fetch = execute.call_args_list
        self.assertEqual(config.args[0], ['git', 'config', '--local', '--includes', '--name-only', '--list'])
        self.assertEqual(config.args[2], 10)
        self.assertEqual(fetch.args[0], ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                                       '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                                       '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                                       'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                                       'https://github.com/liboyang42-cpu/chengyin-ios.git',
                                       '54f708eb260ad20cdf0fb6355cc4eaedb967019a'])
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

    def test_54f_credential_redirect_include_and_auth_configuration_fail_before_fetch(self):
        keys = ('credential.helper', 'credential.https://github.com.username', 'http.extraheader',
                'http.https://github.com/.extraheader', 'http.proxy', 'url.ssh://example.invalid.insteadof',
                'include.path', 'includeif.gitdir:work.path', 'core.askpass', 'extensions.worktreeconfig')
        for key in keys:
            with self.subTest(key=key), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', return_value=(0, (key + '\n').encode())) as execute, self.assertRaises(ValueError):
                runner.ensure_casefold_commit(BYTEPERF_SOURCE)
            self.assertEqual(execute.call_count, 1)

    def test_54f_unreadable_config_offline_and_timeout_fail_closed_without_retry(self):
        for mode in ('config', 'offline', 'timeout'):
            outputs = [(1, b'')] if mode == 'config' else [(0, b'core.bare\n'), (124 if mode == 'timeout' else 1, b'')]
            with self.subTest(mode=mode), mock.patch.object(runner, 'checked', side_effect=self.missing), \
                 mock.patch.object(runner, 'execute', side_effect=outputs) as execute, self.assertRaises(ValueError):
                runner.ensure_casefold_commit(BYTEPERF_SOURCE)
            self.assertEqual(execute.call_count, 1 if mode == 'config' else 2)

    def test_existing_or_fetched_54f_wrong_tree_parent_merge_or_missing_headers_fail(self):
        bad_headers = (self.headers().replace(runner.CASEFOLD_BASE_TREE, '0' * 40),
                       self.headers().replace(runner.PATHFIX_BASE_COMMIT, runner.BASE_COMMIT),
                       self.headers().replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n'),
                       self.headers().replace('tree ' + runner.CASEFOLD_BASE_TREE + '\n', ''),
                       self.headers().replace('parent ' + runner.PATHFIX_BASE_COMMIT + '\n', ''),
                       self.headers().replace('\nparent ', '\ntree ' + runner.CASEFOLD_BASE_TREE + '\nparent ', 1))
        for existing in (True, False):
            for bad in bad_headers:
                def read(command, root):
                    if command[1:3] == ['cat-file', '-e']:
                        if existing: return ''
                        raise ValueError('Synthetic missing 54f')
                    return bad
                with self.subTest(existing=existing, headers=bad), mock.patch.object(runner, 'checked', side_effect=read), \
                     mock.patch.object(runner, 'execute', side_effect=[(0, b'core.bare\n'), (0, b'')]) as execute, self.assertRaises(ValueError):
                    runner.ensure_casefold_commit(BYTEPERF_SOURCE)
                self.assertEqual(execute.call_count, 0 if existing else 2)

    def test_fixed_54f_public_object_identity_cannot_be_generalized(self):
        for key in ('CASEFOLD_BASE_COMMIT', 'CASEFOLD_BASE_TREE'):
            with self.subTest(key=key), mock.patch.object(runner, key, '0' * 40), \
                 mock.patch.object(runner, 'checked') as read, mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_casefold_commit(BYTEPERF_SOURCE)
            read.assert_not_called(); execute.assert_not_called()



# MERCHANT_READBACK_TESTS_BEGIN
class MerchantReadbackBoundary(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='merchant-current-six-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve(strict=True)
        for relative in runner.MERCHANT_PATHS:
            path = root / relative; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((MERCHANT_SOURCE / relative).read_bytes())
        return root

    def receipt(self):
        r, expected = ReceiptIdentity().receipt()
        for prefix, commit, tree, name in (
            ('native', runner.NATIVE_BASE_COMMIT, runner.NATIVE_BASE_TREE, runner.NATIVE_NAME),
            ('portable', runner.PORTABLE_BASE_COMMIT, runner.PORTABLE_BASE_TREE, runner.PORTABLE_LAYER['name']),
            ('description', runner.DESCRIPTION_BASE_COMMIT, runner.DESCRIPTION_BASE_TREE, runner.DESCRIPTION_LAYER['name']),
            ('social', runner.SOCIAL_BASE_COMMIT, runner.SOCIAL_BASE_TREE, runner.SOCIAL_LAYER['name']),
            ('pathfix', runner.PATHFIX_BASE_COMMIT, runner.PATHFIX_BASE_TREE, runner.PATHFIX_NAME),
            ('casefold', runner.CASEFOLD_BASE_COMMIT, runner.CASEFOLD_BASE_TREE, runner.CASEFOLD_NAME),
            ('byteperf', runner.BYTEPERF_BASE_COMMIT, runner.BYTEPERF_BASE_TREE, runner.BYTEPERF_NAME),
            ('merchant', runner.MERCHANT_BASE_COMMIT, runner.MERCHANT_BASE_TREE, runner.MERCHANT_NAME)):
            r.update({prefix + '_base_commit': commit, prefix + '_base_tree': tree, prefix + '_selection': name})
        r.update(selection=runner.MERCHANT_NAME, expected_count=71, actual_count=71)
        methods = MERCHANT_SELECTION['groups'][0]['methods']
        r['groups']['core'].update(expected=methods, actual_count=50,
                                  actual=[{'method': m, 'status': 'Passed'} for m in methods])
        return r, expected

    def test_original212_complete_methods_and_full_predecessor_files_are_exact(self):
        current = (MERCHANT_SOURCE / runner.PATHS[3]).read_bytes()
        old = runner.merchant_test_preimage(current)
        def blocks(raw):
            lines = raw.splitlines(True); result = {}
            for cls in ast.parse(raw).body:
                if not isinstance(cls, ast.ClassDef) or cls.name in {'MerchantReadbackBoundary', 'Split71PartitionProtocol'}: continue
                for node in cls.body:
                    if isinstance(node, ast.FunctionDef) and node.name.startswith('test_'):
                        key = cls.name + '.' + node.name
                        self.assertNotIn(key, result)
                        start = min([node.lineno] + [d.lineno for d in node.decorator_list])
                        result[key] = b''.join(lines[start - 1:node.end_lineno])
            return result
        self.assertEqual(len(blocks(old)), 212); self.assertEqual(blocks(current), blocks(old))
        self.assertEqual(runner.hashlib.sha256(old).hexdigest(), runner.BYTEPERF_TEST_SHA256)
        current_runner = (MERCHANT_SOURCE / runner.PATHS[2]).read_bytes()
        prior_runner = runner.merchant_runner_preimage(current_runner)
        self.assertEqual(runner.blob_id(prior_runner), runner.MERCHANT_BEFORE[runner.PATHS[2]]['blob'])
        for raw, inverse in ((current, runner.merchant_test_preimage), (current_runner, runner.merchant_runner_preimage)):
            with self.assertRaises(ValueError): inverse(b'# off-hunk\n' + raw)
            with self.assertRaises(ValueError): inverse(raw.replace(b'\n', b'\r\n'))

    def test_exact_current71_retains_all65_and_six_real_new_source_bindings(self):
        self.assertEqual(runner.validate_merchant_selection(MERCHANT_SELECTION, MERCHANT_SOURCE), MERCHANT_SELECTION)
        old = runner.merchant_predecessor_selection(MERCHANT_SELECTION)
        self.assertEqual(old, BYTEPERF_SELECTION)
        self.assertEqual([len(g['methods']) for g in MERCHANT_SELECTION['groups']], [50, 14, 7])
        before = {m for g in old['groups'] for m in g['methods']}
        after = {m for g in MERCHANT_SELECTION['groups'] for m in g['methods']}
        self.assertEqual(len(before), 65); self.assertEqual(after - before, set(runner.MERCHANT_METHODS))
        self.assertEqual(before - after, set())
        self.assertEqual(len(runner.MERCHANT_PATHS), 7)
        self.assertEqual(runner.MERCHANT_BASE_COMMIT, '7bf858c23374b808c6d932367f96e97d09e9d799')
        self.assertEqual(runner.MERCHANT_BASE_TREE, '94f43a19209607d403b47f3cdada1cfadf9c9aba')

    def test_old_defaults_reject_current71_and_current_rejects_old65(self):
        with self.assertRaises(ValueError): runner.validate_byteperf_selection(MERCHANT_SELECTION, MERCHANT_SOURCE)
        with self.assertRaises(ValueError): runner.validate_merchant_selection(BYTEPERF_SELECTION, MERCHANT_SOURCE)
        with self.assertRaises((ValueError, OSError)): runner.validate_merchant_selection(MERCHANT_SELECTION, self.fixture())

    def test_each_new_method_missing_duplicate_extra_wrong_source_and_old_recount_reject(self):
        for method in runner.MERCHANT_METHODS:
            for kind in ('missing', 'duplicate', 'extra', 'source'):
                value = copy.deepcopy(MERCHANT_SELECTION); group = value['groups'][0]
                if kind == 'missing': group['methods'].remove(method)
                elif kind == 'duplicate': group['methods'].append(method)
                elif kind == 'extra': group['methods'].append(method + 'Invented')
                else: next(r for r in group['method_sources'] if r['method'] == method)['source'] = 'Tests/CoreTests/ProfileEditTests.swift'
                with self.subTest(method=method, kind=kind), self.assertRaises(ValueError):
                    runner.merchant_predecessor_selection(value)
        for key in ('merchant_readback', 'bounded_byte_transform_repair', 'casefold_fixture_repair'):
            value = copy.deepcopy(MERCHANT_SELECTION); del value[key]
            with self.assertRaises(ValueError): runner.merchant_predecessor_selection(value)

    def test_warm_current_six_reject_same_stat_missing_symlink_and_hardlink_aliases(self):
        root = self.fixture(); runner.merchant_current_inputs(MERCHANT_SELECTION, root)
        for relative in runner.MERCHANT_PATHS:
            path = root / relative; raw = path.read_bytes(); stat = path.stat()
            path.write_bytes(bytes([raw[0] ^ 1]) + raw[1:]); os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            with self.subTest(path=relative), self.assertRaises(ValueError): runner.merchant_current_inputs(MERCHANT_SELECTION, root)
            path.unlink()
            with self.assertRaises((ValueError, OSError)): runner.merchant_current_inputs(MERCHANT_SELECTION, root)
            path.symlink_to(MERCHANT_SOURCE / relative)
            with self.assertRaises(ValueError): runner.merchant_current_inputs(MERCHANT_SELECTION, root)
            path.unlink(); path.write_bytes(raw)
            alias = root / 'alias'; os.link(path, alias)
            with self.assertRaises(ValueError): runner.merchant_current_inputs(MERCHANT_SELECTION, root)
            alias.unlink()
        runner.merchant_current_inputs(MERCHANT_SELECTION, root)

    def test_root_and_ancestor_links_and_noncanonical_json_fail(self):
        root = self.fixture(); parent = root / 'linked'; parent.symlink_to(root, target_is_directory=True)
        with self.assertRaises(ValueError): runner.merchant_current_inputs(MERCHANT_SELECTION, parent)
        parent.unlink()
        folder = root / 'Core'; folder.rename(root / 'actual-core'); folder.symlink_to(root / 'actual-core', target_is_directory=True)
        with self.assertRaises(ValueError): runner.merchant_current_inputs(MERCHANT_SELECTION, root)
        root = self.fixture(); path = root / runner.PATHS[1]; raw = path.read_bytes()
        for changed in (raw + b'\n', raw.replace(b'\n', b'\r\n'), json.dumps(MERCHANT_SELECTION).encode()):
            path.write_bytes(changed)
            with self.assertRaises(ValueError): runner.merchant_current_inputs(MERCHANT_SELECTION, root)

    def test_projection_is_explicit_readonly_same_root_and_reauthenticates_after_warm(self):
        root = self.fixture(); view = runner.merchant_history_root(MERCHANT_SELECTION, root)
        self.assertEqual(os.fspath(view), str(root)); self.assertEqual(view.resolve(), root.resolve())
        self.assertEqual(runner.read_json(view / runner.PATHS[1]), BYTEPERF_SELECTION)
        self.assertEqual(runner.digest(view / runner.PATHS[3]), runner.BYTEPERF_TEST_SHA256)
        self.assertEqual((view / runner.PATHS[2]).read_bytes(), (root / runner.PATHS[2]).read_bytes())
        with self.assertRaises(ValueError): view / '/tmp/outside'
        with self.assertRaises(ValueError): view / '../outside'
        with self.assertRaises(ValueError): (view / runner.PATHS[1]).open('wb')
        for path in view.overrides:
            real = root / path; raw = real.read_bytes(); st = real.stat()
            real.write_bytes(raw[:-1] + b' '); os.utime(real, ns=(st.st_atime_ns, st.st_mtime_ns))
            with self.assertRaises(ValueError): (view / path).read_bytes()
            real.write_bytes(raw)

    def test_coherent_payload_repin_cannot_replace_complete_predecessor_or_frozen_postimage(self):
        root = self.fixture()
        for index, row in enumerate(runner.MERCHANT_LAYER['payload']):
            path = root / row['path']; raw = path.read_bytes(); changed = raw + b'\n# off-hunk\n'; path.write_bytes(changed)
            selection = copy.deepcopy(MERCHANT_SELECTION); layer = selection['merchant_readback']; target = layer['payload'][index]
            target['after_sha256'] = runner.hashlib.sha256(changed).hexdigest(); target['after_blob'] = runner.blob_id(changed)
            with mock.patch.object(runner, 'MERCHANT_LAYER', layer), mock.patch.object(runner, 'MERCHANT_SELECTION_SHA256', runner.hashlib.sha256(runner.encode(selection).encode()).hexdigest()), self.assertRaises(ValueError):
                runner.merchant_current_inputs(selection, root)
            path.write_bytes(raw)
        for key in ('MERCHANT_SELECTION_RAW_SHA256', 'MERCHANT_TEST_SHA256', 'MERCHANT_LAYER_SHA256'):
            with mock.patch.object(runner, key, '0' * 64), self.assertRaises(ValueError): runner.merchant_current_inputs(MERCHANT_SELECTION, root)

    def test_current_core_filter_selects_all50_and_each_new_method_exactly(self):
        group = MERCHANT_SELECTION['groups'][0]; command = runner.core_command(group, Path('synthetic.xml'))
        pattern = command[command.index('--filter') + 1]
        self.assertEqual(len(group['methods']), 50)
        for method in group['methods']:
            target, cls, name = method.split('/'); exact = target + '.' + cls + '/' + name
            self.assertIsNotNone(re.fullmatch(pattern, exact)); self.assertIsNone(re.fullmatch(pattern, exact + 'Extra'))
        self.assertIn('--skip-build', command); self.assertNotIn('.*', pattern)

    def test_core50_requires_both_real_streams_and_every_new_method(self):
        methods = MERCHANT_SELECTION['groups'][0]['methods']
        xml = Creator65Contract.xml(methods)
        transcript = core_transcript(methods)
        self.assertEqual(len(runner.validate_core_evidence(xml, transcript, methods, 0)), 50)
        for method in runner.MERCHANT_METHODS:
            missing = [m for m in methods if m != method]
            for actual_xml, actual_transcript in ((Creator65Contract.xml(missing), transcript), (xml, core_transcript(missing))):
                with self.subTest(method=method), self.assertRaises(ValueError):
                    runner.validate_core_evidence(actual_xml, actual_transcript, methods, 0)
        for returncode in (1, 124, -15):
            with self.assertRaises(ValueError): runner.validate_core_evidence(xml, transcript, methods, returncode)

    def test_current71_receipt_rejects_old65_missing_each_new_and_forged_counter(self):
        r, expected = self.receipt(); runner.validate_merchant_pass_receipt(r, expected, MERCHANT_SELECTION)
        for method in runner.MERCHANT_METHODS:
            changed = copy.deepcopy(r)
            changed['groups']['core']['actual'] = [x for x in changed['groups']['core']['actual'] if x['method'] != method]
            with self.subTest(method=method), self.assertRaises(ValueError): runner.validate_merchant_pass_receipt(changed, expected, MERCHANT_SELECTION)
        for key in ('expected_count', 'actual_count'):
            for value in (65, 70, True, '71'):
                changed = copy.deepcopy(r); changed[key] = value
                with self.assertRaises(ValueError): runner.validate_merchant_pass_receipt(changed, expected, MERCHANT_SELECTION)
        changed = copy.deepcopy(r); changed['groups']['core']['actual'] = changed['groups']['core']['actual'][:44]
        with self.assertRaises(ValueError): runner.validate_merchant_pass_receipt(changed, expected, MERCHANT_SELECTION)

    def test_receipt_preserves_every_historical_identity_and_result_digest_requirement(self):
        r, expected = self.receipt()
        for key in [k for k in r if k.endswith(('_base_commit', '_base_tree', '_selection'))] + list(expected):
            changed = copy.deepcopy(r); changed[key] = 'wrong'
            with self.subTest(key=key), self.assertRaises(ValueError): runner.validate_merchant_pass_receipt(changed, expected, MERCHANT_SELECTION)
        for field in ('build_returncode', 'result_sha256', 'transcript_sha256'):
            changed = copy.deepcopy(r); del changed['groups']['core'][field]
            with self.assertRaises(ValueError): runner.validate_merchant_pass_receipt(changed, expected, MERCHANT_SELECTION)
        for status in ('Failed', 'Skipped', 'Unknown'):
            changed = copy.deepcopy(r); changed['groups']['core']['actual'][0]['status'] = status
            with self.assertRaises(ValueError): runner.validate_merchant_pass_receipt(changed, expected, MERCHANT_SELECTION)
        changed = copy.deepcopy(r); changed['groups']['core']['actual'].append(changed['groups']['core']['actual'][0])
        with self.assertRaises(ValueError): runner.validate_merchant_pass_receipt(changed, expected, MERCHANT_SELECTION)

    def test_current_receipt_initialization_is71_and_legacy_initialization_stays65(self):
        with tempfile.TemporaryDirectory() as tmp:
            current = runner.MerchantDiagnostic(MERCHANT_SOURCE, Path(tmp), MERCHANT_SELECTION)
            legacy = runner.Diagnostic(BYTEPERF_SOURCE, Path(tmp), BYTEPERF_SELECTION)
            self.assertEqual(current.receipt['expected_count'], 71); self.assertEqual(current.receipt['actual_count'], 0)
            self.assertEqual(legacy.receipt['expected_count'], 65)
            self.assertEqual(len(current.receipt['groups']['core']['expected']), 50)

    def tree_records(self, before):
        if before: return {p: ['100644', 'blob', v['blob']] for p, v in runner.MERCHANT_BEFORE.items()}
        return {p: ['100644', 'blob', runner.blob_id((MERCHANT_SOURCE / p).read_bytes())] for p in runner.MERCHANT_PATHS}

    def test_each_before_and_after_tree_path_mode_type_blob_and_addition_absence(self):
        for before in (True, False):
            records = self.tree_records(before)
            with mock.patch.object(runner, 'merchant_tree_entries', return_value=records):
                self.assertEqual(runner.verify_merchant_tree(MERCHANT_SOURCE, 'synthetic-revision', before=before), records)
            for path in records:
                for field, value in ((0, '100755'), (0, '120000'), (1, 'tree'), (2, '0' * 40)):
                    changed = copy.deepcopy(records); changed[path][field] = value
                    with mock.patch.object(runner, 'merchant_tree_entries', return_value=changed), self.assertRaises(ValueError):
                        runner.verify_merchant_tree(MERCHANT_SOURCE, 'synthetic-revision', before=before)
                changed = copy.deepcopy(records); del changed[path]
                with mock.patch.object(runner, 'merchant_tree_entries', return_value=changed), self.assertRaises(ValueError):
                    runner.verify_merchant_tree(MERCHANT_SOURCE, 'synthetic-revision', before=before)
            changed = copy.deepcopy(records); changed['unexpected'] = ['100644', 'blob', 'a' * 40]
            with mock.patch.object(runner, 'merchant_tree_entries', return_value=changed), self.assertRaises(ValueError):
                runner.verify_merchant_tree(MERCHANT_SOURCE, 'synthetic-revision', before=before)

    def full_tree_records(self, before):
        records = self.tree_records(before)
        for path in runner.MERCHANT_PATHS:
            for parent in Path(path).parents:
                if str(parent) != '.': records[str(parent)] = ['040000', 'tree', 'd' * 40]
        records['untouched.txt'] = ['100644', 'blob', 'c' * 40]
        return records

    def transport(self, command, root):
        if command == ['git', 'rev-parse', 'HEAD']: return 'a' * 40
        if command == ['git', 'rev-parse', 'HEAD^{tree}']: return runner.merchant_tree_id(self.full_tree_records(False))
        if command == ['git', 'cat-file', '-p', 'a' * 40]: return 'tree ' + runner.merchant_tree_id(self.full_tree_records(False)) + '\nparent ' + runner.MERCHANT_BASE_COMMIT + '\n\nSynthetic candidate'
        if command == ['git', 'rev-parse', runner.MERCHANT_BASE_COMMIT + '^{tree}']: return runner.MERCHANT_BASE_TREE
        if command[1] == 'diff': return '\n'.join(runner.MERCHANT_LAYER['allowed_changes'])
        if command[1] == 'status': return ''
        if command[1] == 'ls-tree':
            before = (command[5] if '-t' in command else command[4]) == runner.MERCHANT_BASE_COMMIT
            records = self.tree_records(before) if '--' in command else self.full_tree_records(before)
            return '\0'.join(' '.join(v) + '\t' + p for p, v in records.items()) + '\0'
        raise AssertionError(command)

    def test_scope_exact_six_full_trees_githubsha_parent_and_dirty_guards(self):
        with mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=self.transport), mock.patch.object(runner, 'verify_merchant_published_history', return_value={'old_chain': 'synthetic'}) as history:
            self.assertEqual(runner.verify_merchant_scope(MERCHANT_SOURCE, MERCHANT_SELECTION)['source_tree'], runner.merchant_tree_id(self.full_tree_records(False)))
            history.assert_called_once()
        for kind in ('witness', 'merge', 'tree', 'extra', 'missing', 'status', 'dirty', 'offscope-mode', 'empty-tree', 'head-tree'):
            def changed(command, root):
                value = self.transport(command, root)
                if command[1:3] == ['cat-file', '-p']:
                    if kind == 'witness': return value.replace(runner.MERCHANT_BASE_COMMIT, '88d46ef18331bdb8176f62421399ef468366f233')
                    if kind == 'merge': return value.replace('\n\n', '\nparent ' + 'f' * 40 + '\n\n')
                if command == ['git', 'rev-parse', runner.MERCHANT_BASE_COMMIT + '^{tree}'] and kind == 'tree': return '0' * 40
                if command[1] == 'diff':
                    if kind == 'extra': return value + '\nM\tApp/Unrelated.swift'
                    if kind == 'missing': return '\n'.join(value.splitlines()[1:])
                    if kind == 'status': return value.replace('A\t', 'M\t')
                if command[1] == 'status' and kind == 'dirty': return ' M Core/Unrelated.swift'
                if command[1] == 'ls-tree' and '--' not in command and command[5] == 'a' * 40 and kind == 'empty-tree': return value + '040000 tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\textra-empty\0'
                if command == ['git', 'rev-parse', 'HEAD^{tree}'] and kind == 'head-tree': return 'e' * 40
                if command[1] == 'ls-tree' and '--' not in command and command[5] == 'a' * 40 and kind == 'offscope-mode': return value.replace('100644 blob ' + 'c' * 40, '100755 blob ' + 'c' * 40)
                return value
            with self.subTest(kind=kind), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}), mock.patch.object(runner, 'checked', side_effect=changed), mock.patch.object(runner, 'verify_merchant_published_history', return_value={}), self.assertRaises(ValueError):
                runner.verify_merchant_scope(MERCHANT_SOURCE, MERCHANT_SELECTION)

    def test_missing_real_parent_fails_without_fetch_or_alternate_object_acquisition(self):
        with mock.patch.object(runner, 'checked', side_effect=ValueError('Synthetic missing actual7bf')), mock.patch.object(runner, 'execute') as execution, mock.patch.object(runner, 'ensure_casefold_commit') as ensure, self.assertRaises(ValueError):
            runner.verify_merchant_published_history(MERCHANT_SOURCE, MERCHANT_SELECTION)
        execution.assert_not_called(); ensure.assert_not_called()

    def test_report_missing_receipt_stays_not_run_without_scope_or_execution(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch('builtins.print') as output, mock.patch.object(runner, 'verify_merchant_scope') as scope:
            runner.merchant_report(Path(tmp), None, MERCHANT_SOURCE)
            self.assertIn('NOT_RUN', output.call_args.args[0]); scope.assert_not_called()

    def test_report_revalidates_current50_xml_transcript_and_every_exported_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp); receipt, expected = self.receipt()
            expected['selection_sha256'] = runner.digest(MERCHANT_SOURCE / runner.PATHS[1]); receipt['selection_sha256'] = expected['selection_sha256']
            methods = MERCHANT_SELECTION['groups'][0]['methods']
            (output / 'core.xml').write_bytes(Creator65Contract.xml(methods))
            (output / 'core-stdout.txt').write_bytes(core_transcript(methods))
            receipt['groups']['core']['result_sha256'] = runner.digest(output / 'core.xml')
            receipt['groups']['core']['transcript_sha256'] = runner.digest(output / 'core-stdout.txt')
            for group in MERCHANT_SELECTION['groups'][1:]:
                for part, data in [('summary', summary(len(group['methods']))), ('tests', xctests(group['methods'], group['target']))]:
                    file = output / (group['name'] + '-' + part + '.json'); runner.write_json(file, data)
                    receipt['groups'][group['name']][part + '_sha256'] = runner.digest(file)
            runner.write_json(output / 'receipt.json', receipt)
            env = {key: expected[field] for key, field in [('GITHUB_SHA','source_sha'), ('GITHUB_WORKFLOW_SHA','workflow_sha'), ('GITHUB_RUN_ID','run_id'), ('GITHUB_RUN_ATTEMPT','run_attempt')]}
            with mock.patch.dict(os.environ, env), mock.patch.object(runner, 'checked', return_value=expected['source_tree']), mock.patch.object(runner, 'verify_merchant_scope'), mock.patch('builtins.print'):
                runner.merchant_report(output, output / 'summary', MERCHANT_SOURCE)
                self.assertIn('71 / 71', (output / 'summary').read_text())
                for name in ('core.xml', 'core-stdout.txt', 'app-unit-tests.json', 'ui-summary.json'):
                    path = output / name; raw = path.read_bytes(); path.write_bytes(raw + b' ')
                    with self.subTest(file=name), self.assertRaises(ValueError): runner.merchant_report(output, None, MERCHANT_SOURCE)
                    path.write_bytes(raw)

    def history_transport(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        if command == ['git', 'cat-file', '-p', runner.MERCHANT_BASE_COMMIT]:
            return 'tree ' + runner.MERCHANT_BASE_TREE + '\nparent ' + runner.BYTEPERF_BASE_COMMIT + '\n\nSynthetic published7bf'
        if command == ['git', 'cat-file', '-p', runner.BYTEPERF_BASE_COMMIT]: return 'tree ' + runner.BYTEPERF_BASE_TREE + '\nparent ' + runner.CASEFOLD_BASE_COMMIT + '\n\nSynthetic c3a'
        if command == ['git', 'cat-file', '-p', runner.CASEFOLD_BASE_COMMIT]: return 'tree ' + runner.CASEFOLD_BASE_TREE + '\nparent ' + runner.PATHFIX_BASE_COMMIT + '\n\nSynthetic54f'
        if command == ['git', 'rev-parse', runner.BYTEPERF_BASE_COMMIT + '^{tree}']: return runner.BYTEPERF_BASE_TREE
        if command[1] == 'diff':
            self.assertEqual(command, ['git', 'diff', '--name-status', '--no-renames', runner.BYTEPERF_BASE_COMMIT, runner.MERCHANT_BASE_COMMIT])
            return '\n'.join(runner.BYTEPERF_LAYER['allowed_changes'])
        if command[1] == 'ls-tree':
            if '-r' in command:
                self.assertEqual(command[4], runner.MERCHANT_BASE_COMMIT)
                rows = {p: ['100644', 'blob', runner.blob_id((BYTEPERF_SOURCE / p).read_bytes())] for p in runner.BYTEPERF_PATHS}
                rows[runner.PATHS[2]][2] = runner.MERCHANT_BEFORE[runner.PATHS[2]]['blob']
            else:
                self.assertEqual(command[3], runner.BYTEPERF_BASE_COMMIT)
                rows = {p: ['100644', 'blob', oid] for p, oid in runner.BYTEPERF_BEFORE_BLOBS.items()}
                rows.update({r['path']: ['100644', 'blob', r['before_blob']] for r in runner.BYTEPERF_LAYER['payload'] if r['status'] == 'M'})
            return '\0'.join(' '.join(v) + '\t' + p for p, v in rows.items()) + '\0'
        raise AssertionError(command)

    def test_published7bf_nine_path_bridge_reaches_exact_c3_history_without_network(self):
        with mock.patch.object(runner, 'checked', side_effect=self.history_transport) as read, mock.patch.object(runner, 'verify_casefold_scope', return_value={'historical': 'synthetic'}) as history, mock.patch.object(runner, 'execute') as execute:
            actual = runner.verify_merchant_published_history(MERCHANT_SOURCE, MERCHANT_SELECTION)
        self.assertEqual(actual['byteperf_base_commit'], runner.BYTEPERF_BASE_COMMIT)
        self.assertEqual(history.call_count, 1)
        view, old = history.call_args.args
        self.assertIsInstance(view, runner.MerchantHistoryPath); self.assertEqual(view.root, MERCHANT_SOURCE)
        self.assertEqual(old, runner.byteperf_predecessor_selection(BYTEPERF_SELECTION))
        self.assertEqual(history.call_args.kwargs, {'published_revision': runner.BYTEPERF_BASE_COMMIT})
        probes = [c.args[0][-1] for c in read.call_args_list if c.args[0][1:3] == ['cat-file', '-e']]
        self.assertIn(runner.MERCHANT_BASE_COMMIT + '^{commit}', probes)
        self.assertIn(runner.MERCHANT_BASE_COMMIT + '^{tree}', probes)
        self.assertEqual(len(probes), 10); execute.assert_not_called()

    def test_published_bridge_rejects_wrong_headers_diff_every_mode_blob_and_old_chain(self):
        for kind in ('parent', 'merge', 'tree', 'c3tree', 'missing', 'extra', 'status'):
            def changed(command, root):
                raw = self.history_transport(command, root)
                if command[1:3] == ['cat-file', '-p']:
                    if kind == 'parent': return raw.replace(runner.BYTEPERF_BASE_COMMIT, runner.CASEFOLD_BASE_COMMIT)
                    if kind == 'merge': return raw.replace('\n\n', '\nparent ' + 'a' * 40 + '\n\n')
                    if kind == 'tree': return raw.replace(runner.MERCHANT_BASE_TREE, '0' * 40)
                if command[1] == 'rev-parse' and kind == 'c3tree': return '0' * 40
                if command[1] == 'diff':
                    if kind == 'missing': return '\n'.join(raw.splitlines()[1:])
                    if kind == 'extra': return raw + '\nM\tunexpected'
                    if kind == 'status': return raw.replace('A\t', 'M\t')
                return raw
            with self.subTest(kind=kind), mock.patch.object(runner, 'checked', side_effect=changed), mock.patch.object(runner, 'verify_casefold_scope') as history, self.assertRaises(ValueError):
                runner.verify_merchant_published_history(MERCHANT_SOURCE, MERCHANT_SELECTION)
            history.assert_not_called()
        for before in (True, False):
            paths = list(runner.BYTEPERF_BEFORE_BLOBS) + [r['path'] for r in runner.BYTEPERF_LAYER['payload'] if r['status'] == 'M'] if before else list(runner.BYTEPERF_PATHS)
            for path in paths:
                for field, replacement in ((0, '100755'), (1, 'tree'), (2, '0' * 40)):
                    def changed(command, root):
                        raw = self.history_transport(command, root)
                        if command[1] == 'ls-tree' and ('-r' not in command) == before:
                            rows = raw.split('\0')
                            for index, row in enumerate(rows):
                                if row.endswith('\t' + path):
                                    meta, name = row.split('\t'); parts = meta.split(' '); parts[field] = replacement
                                    rows[index] = ' '.join(parts) + '\t' + name
                            return '\0'.join(rows)
                        return raw
                    with self.subTest(before=before, path=path, field=field), mock.patch.object(runner, 'checked', side_effect=changed), mock.patch.object(runner, 'verify_casefold_scope') as history, self.assertRaises(ValueError):
                        runner.verify_merchant_published_history(MERCHANT_SOURCE, MERCHANT_SELECTION)
                    history.assert_not_called()
        with mock.patch.object(runner, 'checked', side_effect=self.history_transport), mock.patch.object(runner, 'verify_casefold_scope', side_effect=ValueError('Synthetic corrupt older layer')), self.assertRaises(ValueError):
            runner.verify_merchant_published_history(MERCHANT_SOURCE, MERCHANT_SELECTION)

    def test_present_commit_missing_tree_stops_before_any_legacy_fetch_helper(self):
        def read(command, root):
            self.assertEqual(command[1:3], ['cat-file', '-e'])
            if command[-1].endswith('^{tree}'): raise ValueError('Synthetic missing tree')
            return ''
        with mock.patch.object(runner, 'checked', side_effect=read), mock.patch.object(runner, 'execute') as execute, mock.patch.object(runner, 'verify_casefold_scope') as history, self.assertRaises(ValueError):
            runner.verify_merchant_published_history(MERCHANT_SOURCE, MERCHANT_SELECTION)
        execute.assert_not_called(); history.assert_not_called()

    def test_complete_tree_reconstruction_authenticates_empty_trees_and_directory_modes(self):
        self.assertEqual(runner.merchant_tree_id({}), '4b825dc642cb6eb9a060e54bf8d69288fbee4904')
        leaf = runner.blob_id(b'synthetic')
        nested = b'100644 item\0' + bytes.fromhex(leaf)
        nested_id = runner.hashlib.sha1(b'tree ' + str(len(nested)).encode() + b'\0' + nested).hexdigest()
        raw = b'40000 folder\0' + bytes.fromhex(nested_id)
        expected = runner.hashlib.sha1(b'tree ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        entries = {'folder': ['040000', 'tree', nested_id], 'folder/item': ['100644', 'blob', leaf]}
        self.assertEqual(runner.merchant_tree_id(entries), expected)
        changed = copy.deepcopy(entries); changed['empty'] = ['040000', 'tree', '4b825dc642cb6eb9a060e54bf8d69288fbee4904']
        self.assertNotEqual(runner.merchant_tree_id(changed), expected)
        del changed['folder']
        with self.assertRaises(ValueError): runner.merchant_tree_id(changed)

    def test_cli_alias_source_root_is_rejected_before_normalizing_it_away(self):
        with tempfile.TemporaryDirectory() as tmp:
            alias = Path(tmp) / 'alias'; alias.symlink_to(MERCHANT_SOURCE, target_is_directory=True)
            with mock.patch.object(sys, 'argv', ['runner', 'validate', '--source-root', str(alias)]), self.assertRaises(ValueError): runner.main()


    def c3_headers(self):
        return 'tree ' + runner.BYTEPERF_BASE_TREE + '\nparent ' + runner.CASEFOLD_BASE_COMMIT + '\n\nSynthetic exact c3'

    def c3_present(self, command, root):
        if command[1:3] == ['cat-file', '-e']: return ''
        self.assertEqual(command, ['git', 'cat-file', '-p', runner.BYTEPERF_BASE_COMMIT])
        return self.c3_headers()

    def test_c3_present_never_fetches_and_fixed_target_cannot_be_generalized(self):
        with mock.patch.object(runner, 'checked', side_effect=self.c3_present), mock.patch.object(runner, 'execute') as execute:
            runner.ensure_merchant_c3_commit(MERCHANT_SOURCE)
        execute.assert_not_called()
        for key in ('BYTEPERF_BASE_COMMIT', 'BYTEPERF_BASE_TREE'):
            with mock.patch.object(runner, key, '0' * 40), mock.patch.object(runner, 'checked') as read, mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_merchant_c3_commit(MERCHANT_SOURCE)
            read.assert_not_called(); execute.assert_not_called()

    def test_c3_missing_commit_or_tree_fetches_one_exact_public_object_with_safe_environment(self):
        poison = {'GITHUB_TOKEN':'synthetic', 'GH_TOKEN':'synthetic', 'GIT_CONFIG_COUNT':'1',
                  'GIT_CONFIG_KEY_0':'http.extraHeader', 'GIT_CONFIG_VALUE_0':'synthetic',
                  'HTTP_PROXY':'http://example.invalid', 'HTTPS_PROXY':'http://example.invalid',
                  'GIT_SSH_COMMAND':'unexpected', 'GIT_OBJECT_DIRECTORY':'unexpected'}
        for missing in ('commit', 'tree'):
            fetched = []
            def read(command, root):
                if command[-1] == runner.BYTEPERF_BASE_COMMIT + '^{' + missing + '}' and not fetched:
                    raise ValueError('Synthetic missing c3 ' + missing)
                return self.c3_present(command, root)
            def execute(command, root, *args, **kwargs):
                if 'fetch' in command: fetched.append(command)
                return (0, b'core.bare\n') if command[1] == 'config' else (0, b'')
            with self.subTest(missing=missing), mock.patch.dict(os.environ, poison), mock.patch.object(runner, 'checked', side_effect=read), mock.patch.object(runner, 'execute', side_effect=execute) as execution:
                runner.ensure_merchant_c3_commit(MERCHANT_SOURCE)
            self.assertEqual(execution.call_count, 2); config, fetch = execution.call_args_list
            self.assertEqual(config.args[0], ['git','config','--local','--includes','--name-only','--list'])
            self.assertEqual(config.args[2:4], (10, True))
            self.assertEqual(fetch.args[0], ['git','-c','credential.helper=','-c','core.askPass=',
                '-c','http.extraHeader=','-c','http.followRedirects=false','-c','protocol.allow=never',
                '-c','protocol.https.allow=always','fetch','--no-tags','--no-write-fetch-head',
                '--depth=1','--no-recurse-submodules','https://github.com/liboyang42-cpu/chengyin-ios.git',
                'c3a914cd53c0ab60e6d19fc24588d85679dcaa1c'])
            self.assertEqual(fetch.args[2:4], (60, True))
            safe = fetch.kwargs['env']
            self.assertEqual(set(safe), {'PATH','LANG','HOME','GIT_TERMINAL_PROMPT','GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_ASKPASS','SSH_ASKPASS'})
            self.assertEqual(safe['HOME'], '/dev/null'); self.assertEqual(safe['GIT_CONFIG_GLOBAL'], '/dev/null')
            self.assertEqual(safe['GIT_TERMINAL_PROMPT'], '0'); self.assertEqual(safe['GIT_CONFIG_NOSYSTEM'], '1')
            self.assertEqual(config.kwargs['env'], safe); self.assertFalse(set(safe) & set(poison))

    def test_c3_unsafe_configuration_stops_before_fetch(self):
        keys = ('credential.helper','credential.https://github.com.username','http.extraheader',
                'http.https://github.com/.extraheader','http.proxy','url.ssh://example.invalid.insteadof',
                'include.path','includeif.gitdir:work.path','core.askpass','extensions.worktreeconfig')
        for key in keys:
            with self.subTest(key=key), mock.patch.object(runner, 'checked', side_effect=ValueError('Synthetic missing c3')), mock.patch.object(runner, 'execute', return_value=(0,(key+'\n').encode())) as execute, self.assertRaises(ValueError):
                runner.ensure_merchant_c3_commit(MERCHANT_SOURCE)
            self.assertEqual(execute.call_count, 1)

    def test_c3_config_network_timeout_and_success_without_objects_fail_without_retry(self):
        for outputs in ([(1,b'')], [(0,b'core.bare\n'),(1,b'')], [(0,b'core.bare\n'),(124,b'')], [(0,b'core.bare\n'),(0,b'')]):
            with self.subTest(outputs=outputs), mock.patch.object(runner, 'checked', side_effect=ValueError('Synthetic missing object')), mock.patch.object(runner, 'execute', side_effect=outputs) as execute, self.assertRaises(ValueError):
                runner.ensure_merchant_c3_commit(MERCHANT_SOURCE)
            self.assertEqual(execute.call_count, len(outputs))

    def test_c3_wrong_tree_parent_merge_duplicate_or_missing_headers_are_rejected(self):
        headers = self.c3_headers()
        variants = (headers.replace(runner.BYTEPERF_BASE_TREE, '0'*40),
                    headers.replace(runner.CASEFOLD_BASE_COMMIT, runner.PATHFIX_BASE_COMMIT),
                    headers.replace('\n\n', '\nparent '+'f'*40+'\n\n'),
                    headers.replace('tree '+runner.BYTEPERF_BASE_TREE+'\n',''),
                    headers.replace('parent '+runner.CASEFOLD_BASE_COMMIT+'\n',''),
                    headers.replace('\nparent ', '\ntree '+runner.BYTEPERF_BASE_TREE+'\nparent '))
        for bad in variants:
            def read(command, root): return '' if command[1:3] == ['cat-file','-e'] else bad
            with self.subTest(headers=bad), mock.patch.object(runner, 'checked', side_effect=read), mock.patch.object(runner, 'execute') as execute, self.assertRaises(ValueError):
                runner.ensure_merchant_c3_commit(MERCHANT_SOURCE)
            execute.assert_not_called()


    def test_schema_commands_use_exact_observed_result_paths_and_nine_bounded_reads(self):
        paths = {'app-unit': Path('/synthetic/current-app.xcresult'), 'ui': Path('/synthetic/current-ui.xcresult')}
        rows = runner.merchant_schema_commands(paths)
        self.assertEqual(len(rows), 9)
        self.assertEqual(rows[0][1], ['xcrun','xcresulttool','--version'])
        self.assertEqual(rows[3][1], ['xcrun','simctl','list','devices','available','--json'])
        self.assertEqual(rows[4][1], ['xcrun','simctl','list','runtimes','--json'])
        for filename, command, bound in rows[5:]:
            group = 'app-unit' if filename.startswith('app-unit') else 'ui'
            self.assertEqual(command[command.index('--path') + 1], str(paths[group]))
            self.assertEqual(bound, 10 * 1024 * 1024)
        self.assertEqual([limit for _, _, limit in rows[:5]], [1024*1024]*3+[2*1024*1024]*2)

    def test_schema_without_actual_result_is_not_run_and_never_invents_a_default_path(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(runner, 'merchant_capture_command') as command:
            out = Path(tmp); original = {'status':'FAIL','actual_count':0}; saved = copy.deepcopy(original)
            result = runner.merchant_capture_schema(out, out, {}, original)
            self.assertEqual(result['status'], 'NOT_RUN'); self.assertEqual(original, saved)
            command.assert_not_called()
            self.assertEqual(list((out/'schema-evidence').iterdir()), [out/'schema-evidence/manifest.json'])

    def test_schema_raw_bytes_metadata_and_receipt_authority_stay_separate(self):
        raw = b' {"synthetic_schema_fixture":true,"devicesAndConfigurations":[]} \n'
        def capture(command, root, seconds, limit):
            self.assertLessEqual(seconds, 30); self.assertLessEqual(limit, 10*1024*1024)
            return {'argv':command,'status':'CAPTURED','returncode':0,'wall_seconds':0.01,
                    'observed_bytes':{'stdout':len(raw),'stderr':0},'truncated':{'stdout':False,'stderr':False},
                    'stdout':raw,'stderr':b''}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(runner, 'merchant_capture_command', side_effect=capture) as command:
            out=Path(tmp); paths={g:out/(g+'-actual.xcresult') for g in ('app-unit','ui')}
            for p in paths.values():p.mkdir()
            receipt={'status':'FAIL','source_sha':'a'*40,'actual_count':0}; saved=copy.deepcopy(receipt)
            result=runner.merchant_capture_schema(out,out,paths,receipt)
            self.assertEqual(result['status'],'CAPTURED');self.assertFalse(result['native_test_result_authority'])
            self.assertEqual(command.call_count,9);self.assertEqual(receipt,saved)
            self.assertLessEqual(result['retained_bytes'],48*1024*1024)
            for row in result['items']:
                self.assertEqual((out/'schema-evidence'/row['stdout']['file']).read_bytes(),raw)
                self.assertEqual(row['stdout']['sha256'],runner.hashlib.sha256(raw).hexdigest())
                self.assertEqual(row['returncode'],0);self.assertEqual(row['stderr']['byte_count'],0)
            with self.assertRaises(ValueError):runner.merchant_capture_schema(out,out,paths,receipt)

    def test_schema_time_budget_missing_results_links_and_command_failures_are_explicit(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(runner, 'merchant_capture_command') as command:
            out=Path(tmp); path=out/'actual.xcresult';path.mkdir()
            result=runner.merchant_capture_schema(out,out,{'app-unit':path},{},seconds=0)
            command.assert_not_called();self.assertEqual(result['status'],'PARTIAL_OR_FAILED')
            self.assertTrue(all(r['status']=='NOT_RUN' for r in result['items']))
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp); real=out/'actual.xcresult';real.mkdir();link=out/'linked.xcresult';link.symlink_to(real,target_is_directory=True)
            result=runner.merchant_capture_schema(out,out,{'app-unit':link},{})
            self.assertEqual(result['status'],'NOT_RUN')
        failed={'argv':['synthetic'],'status':'EXIT_NONZERO','returncode':1,'wall_seconds':0,
                'observed_bytes':{'stdout':0,'stderr':7},'truncated':{'stdout':False,'stderr':False},'stdout':b'','stderr':b'failure'}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(runner,'merchant_capture_command',side_effect=lambda *args:copy.deepcopy(failed)):
            out=Path(tmp);p=out/'actual.xcresult';p.mkdir()
            result=runner.merchant_capture_schema(out,out,{'app-unit':p},{})
            self.assertEqual(result['status'],'PARTIAL_OR_FAILED');self.assertTrue(any(r['status']=='EXIT_NONZERO' for r in result['items']))

    def test_schema_streaming_limits_and_timeout_are_real_local_process_controls(self):
        # These Python processes test capture mechanics; they are not Apple evidence.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            normal=runner.merchant_capture_command([sys.executable,'-c','import sys;sys.stdout.buffer.write(b"  raw\\n")'],root,2,1024)
            self.assertEqual(normal['status'],'CAPTURED');self.assertEqual(normal['stdout'],b'  raw\n')
            large=runner.merchant_capture_command([sys.executable,'-c','import sys;sys.stdout.buffer.write(b"x"*200000)'],root,2,64)
            self.assertEqual(large['status'],'SIZE_LIMIT');self.assertTrue(large['truncated']['stdout']);self.assertEqual(len(large['stdout']),64)
            slow=runner.merchant_capture_command([sys.executable,'-c','import time;time.sleep(30)'],root,0.9,1024)
            self.assertEqual(slow['status'],'TIMEOUT');self.assertLess(slow['wall_seconds'],1.5)
            error=runner.merchant_capture_command([sys.executable,'-c','import sys;sys.stderr.write("error");sys.exit(2)'],root,2,1024)
            self.assertEqual(error['status'],'EXIT_NONZERO');self.assertEqual(error['returncode'],2);self.assertEqual(error['stderr'],b'error')

    def test_schema_capture_never_rewrites_test_status_and_respects_cancellation(self):
        with tempfile.TemporaryDirectory() as tmp:
            job=runner.MerchantDiagnostic(MERCHANT_SOURCE,Path(tmp),MERCHANT_SELECTION)
            with mock.patch.object(runner.Diagnostic,'run',side_effect=ValueError('Native failure')),mock.patch.object(job,'capture_schema') as capture,self.assertRaisesRegex(ValueError,'Native failure'):
                job.run()
            capture.assert_called_once()
            with mock.patch.object(runner.Diagnostic,'run',side_effect=KeyboardInterrupt),mock.patch.object(job,'capture_schema') as capture,self.assertRaises(KeyboardInterrupt):job.run()
            capture.assert_not_called()
            job.receipt['status']='PASS';before=copy.deepcopy(job.receipt)
            with mock.patch.object(runner,'merchant_capture_schema',side_effect=OSError('Synthetic evidence disk error')),mock.patch('builtins.print') as printed:job.capture_schema()
            self.assertEqual(job.receipt,before);self.assertIn('APPLE_SCHEMA_EVIDENCE_CAPTURE_FAILED',printed.call_args.args[0])

    def test_schema_workflow_is_exact_split_allowlist_and_old_no_artifact_domain_restored(self):
        workflow=(MERCHANT_SOURCE/runner.MERCHANT_WORKFLOW_PATH).read_text()
        old=(BYTEPERF_SOURCE/runner.MERCHANT_WORKFLOW_PATH).read_text()
        self.assertNotIn('upload-artifact',old)
        self.assertEqual(runner.hashlib.sha256(old.encode()).hexdigest(),runner.MERCHANT_BEFORE[runner.MERCHANT_WORKFLOW_PATH]['sha256'])
        self.assertEqual(workflow.count('uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'),2)
        raw=workflow.split('      - name: Preserve bounded raw schema diagnostics even when admission fails\n',1)[1].split('      - name: Record immutable artifact upload start\n',1)[0]
        self.assertIn('if: always()',raw);self.assertIn('retention-days: 1',raw);self.assertIn('overwrite: false',raw)
        names=['manifest.json','xcresult-version.txt','xcresult-summary-help.txt','xcresult-tests-help.txt','simulator-devices.json','simulator-runtimes.json','${{ matrix.result_group }}-summary.json','${{ matrix.result_group }}-tests.json']
        names += [n+'.stderr.txt' for n in names[1:]]
        paths=re.findall(r'^            (.+)$',raw,re.M)
        self.assertEqual(paths,['${{ runner.temp }}/native-targeted-${{ matrix.partition }}/schema-evidence/'+n for n in names])
        for forbidden in ('*','.app','.ipa','archive','secrets.','permissions:','timeout-minutes:','jobs:','workflow_dispatch:','continue-on-error: true'):
            self.assertNotIn(forbidden,raw)
        self.assertEqual(workflow.count('timeout-minutes: 45'),1)
        self.assertIn('partition: [core-app, ui-legacy]',workflow);self.assertIn('max-parallel: 2',workflow)
        self.assertIn('native-schema-71-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.partition }}',workflow)

# BEGIN SPLIT71 PARTITION TESTS
class Split71PartitionProtocol(unittest.TestCase):
    """Synthetic local protocol controls, never native/Apple execution evidence."""
    r = runner

    @classmethod
    def setUpClass(cls):
        cls.selection=cls.r.read_json(MERCHANT_SOURCE/'tools/targeted_native_selection.json')

    def fixture(self):
        r=self.r; selection=self.selection
        identity={'repository':'liboyang42-cpu/chengyin-ios','ref':'refs/heads/migration/native-ios','event':'push',
            'source_sha':'a'*40,'source_tree':'b'*40,'workflow_sha':'a'*40,'run_id':'123','run_attempt':'2',
            'selection_sha256':r.MERCHANT_SELECTION_RAW_SHA256,'partition_table_sha256':r.split71_hash(selection['merchant_readback']['split']['partitions']),
            'source_archive_sha256':'d'*64}
        toolchain={'xcode':'Xcode fixture','developer':'/Applications/Xcode.app','swift':'Swift fixture','sdk_version':'26.5','sdk_path':'/SDK/fixture'}
        artifacts={}
        for number,partition in enumerate(r.SPLIT71_PARTITIONS,1):
            groups=r.split71_groups(selection,partition);simulator={'udid':str(number)*8+'-'+str(number)*4+'-'+str(number)*4+'-'+str(number)*4+'-'+str(number)*12,'name':'iPhone Fixture','runtime':'com.apple.CoreSimulator.SimRuntime.iOS-26-5'}
            receipt=dict(identity,version=2,scope='split71-partition-only',status='PASS',partition=partition,
                artifact_name=r.split71_artifact_name(identity,partition),toolchain=toolchain,simulator=simulator,
                runner_image={'ImageOS':'macos26','ImageVersion':'fixture1','RUNNER_ARCH':'ARM64'},groups={})
            device={'deviceId':simulator['udid'],'deviceName':simulator['name'],'architecture':'arm64','modelName':'iPhone Fixture','platform':'iOS Simulator','osVersion':'26.5','osBuildNumber':'fixture-build'}
            config={'configurationId':'1','configurationName':'Test Scheme Action'}
            runtime={'identifier':simulator['runtime'],'name':'iOS 26.5','version':'26.5','buildversion':'fixture-build'}
            receipt['simulator_runtime']=runtime;receipt['xcresulttool_version']='xcresulttool version fixture'
            docs={'xcresult-version.txt':b'xcresulttool version fixture\n',
                  'simulator-devices.json':(r.encode({'devices':{simulator['runtime']:[dict(name=simulator['name'],udid=simulator['udid'],isAvailable=True)]}})+'\n').encode(),
                  'simulator-runtimes.json':(r.encode({'runtimes':[dict(runtime,isAvailable=True)]})+'\n').encode()}
            fields={'deviceId','deviceName','architecture','modelName','platform','osVersion','osBuildNumber'}
            schemas={'Device':{'type':'object','properties':{key:{'type':'string'} for key in fields},'required':list(fields)},
                'DeviceAndConfigurationSummary':{'properties':dict(device={'$ref':'#/schemas/Device'},testPlanConfiguration={'$ref':'#/schemas/Configuration'},**{key:{'type':'integer'} for key in ('passedTests','failedTests','skippedTests','expectedFailures')})},
                'Tests':{'required':['devices','testPlanConfigurations','testNodes'],'properties':{key:{'type':'array','items':{'$ref':'#/schemas/Device' if key=='devices' else '#/schemas/Configuration'}} for key in ('devices','testPlanConfigurations','testNodes')}}}
            for kind in ('summary','tests'):docs['xcresult-'+kind+'-help.txt']=('SYNTHETIC LOCAL SCHEMA FIXTURE\nCommand output structure (JSON Schema):\n'+r.encode({'schemas':schemas})+'\n').encode()
            for group in groups:
                methods=group['methods'];rows=[{'method':m,'status':'Passed'} for m in methods]
                receipt['groups'][group['name']]={'status':'PASS','expected':methods,'actual_count':len(methods),'actual':rows,'returncode':0}
                if group['kind']=='swift':
                    cases=[];transcript=[]
                    for method in methods:
                        target,klass,test=method.split('/')
                        cases.append('<testcase classname="'+target+'.'+klass+'" name="'+test+'"/>')
                        transcript.extend(["Test Case '-["+target+'.'+klass+' '+test+"]' started.","Test Case '-["+target+'.'+klass+' '+test+"]' passed (0.1 seconds)."])
                    docs['core.xml']=('<testsuite tests="50">'+''.join(cases)+'</testsuite>').encode()
                    docs['core-stdout.txt']=('\n'.join(transcript)+'\n').encode()
                else:
                    docs[group['name']+'-tests.json']=(r.encode({'devices':[device],'testPlanConfigurations':[config],'testNodes':[{'nodeType':'Test Suite','name':group['target'],'children':[{'nodeType':'Test Case','nodeIdentifier':m,'result':'Passed'} for m in methods]}]})+'\n').encode()
                    docs[group['name']+'-summary.json']=(r.encode({'totalTestCount':len(methods),'passedTests':len(methods),'failedTests':0,'skippedTests':0,'expectedFailures':0,'result':'Passed','testFailures':[],'devicesAndConfigurations':[{'device':device,'testPlanConfiguration':config,'passedTests':len(methods),'failedTests':0,'skippedTests':0,'expectedFailures':0}]})+'\n').encode()
            total=sum(len(g['methods']) for g in groups);receipt.update(expected_count=total,actual_count=total)
            name='app-unit' if partition=='core-app' else 'ui';run='fixture.xctestrun'
            ledger=[[run,'file','c'*64]]
            product={'configuration':r.SPLIT71_CONFIGS[name],'xctestrun':run,'xctestrun_sha256':'c'*64}
            if name=='app-unit':
                manifest={'commit':identity['source_sha'],'purpose':'isolated-simulator-app-unit','toolchain':{k:toolchain[k] for k in ('xcode','developer')},'targets':{'QuestifyAppUnitTests':run},'source_archive_sha256':'d'*64}
                raw=(r.encode(manifest)+'\n').encode();docs['app-unit-manifest.json']=raw
                ledger.append(['questify-test-products.json','file',r.hashlib.sha256(raw).hexdigest()]);product['manifest']=manifest
            else:
                docs['ui-config.json']=(r.encode({'QuestifyAPIBaseURL':'','CFBundleSupportedPlatforms':['iPhoneSimulator'],'embedded_mobileprovision':False})+'\n').encode()
                docs['ui-info.plist']=plistlib.dumps({'QuestifyAPIBaseURL':'','CFBundleSupportedPlatforms':['iPhoneSimulator']})
                ledger.append(['Debug-iphonesimulator/Questify.app/Info.plist','file',r.hashlib.sha256(docs['ui-info.plist']).hexdigest()])
                ledger.sort()
            product.update(files=len(ledger),sha256=r.split71_hash(ledger));receipt['products']={name:product}
            receipt['products_before']=copy.deepcopy(receipt['products']);receipt['products_after']=copy.deepcopy(receipt['products'])
            receipt['source_before']={k:identity[k] for k in ('source_sha','source_tree')};receipt['source_after']=dict(receipt['source_before'])
            ledgers={name:ledger}
            if partition=='core-app':
                core_ledger=[['Contents/MacOS/QuestifyCorePackageTests','file','e'*64]]
                receipt['products']['core']={'configuration':r.SPLIT71_CONFIGS['core'],'bundle':'QuestifyCorePackageTests.xctest','files':1,'sha256':r.split71_hash(core_ledger)}
                receipt['products_before']=copy.deepcopy(receipt['products']);receipt['products_after']=copy.deepcopy(receipt['products'])
                ledgers['core']=core_ledger
            docs['products-ledger.json']=(r.encode(ledgers)+'\n').encode()
            phase_names=['checkout-initialization']+sorted(r.split71_phase_names(partition)-{'checkout-initialization','report'})+['report']
            phases={name:{'started_monotonic':float(index+1),'ended_monotonic':float(index+2),'wall_seconds':1.0,'returncode':0} for index,name in enumerate(phase_names)}
            receipt['worker_clock']=r.split71_worker_clock(phases)
            docs['phase-times.json']=(r.encode(phases)+'\n').encode()
            result='/synthetic/'+partition+'/'+('app-unit' if partition=='core-app' else 'ui')+'.xcresult'
            receipt['result_bundle_path']=result;items=[]
            for filename,command,limit in r.split71_schema_rows(partition,Path(result)):
                docs[filename+'.stderr.txt']=b''
                row={'argv':command,'status':'CAPTURED','returncode':0,'wall_seconds':0.1,'observed_bytes':{},'truncated':{'stdout':False,'stderr':False},'file':filename}
                for stream in ('stdout','stderr'):
                    name=filename if stream=='stdout' else filename+'.stderr.txt';raw=docs[name]
                    row[stream]={'file':name,'byte_count':len(raw),'sha256':r.hashlib.sha256(raw).hexdigest()};row['observed_bytes'][stream]=len(raw)
                items.append(row)
            manifest={'version':2,'purpose':'raw-apple-tool-schema-evidence-only','native_test_result_authority':False,'partition':partition,'status':'CAPTURED','identity':identity,'result_bundle_path':result,'limits':{'total_seconds':90,'item_seconds':30,'total_bytes':48*1024*1024,'stderr_item_bytes':64*1024},'items':items,'retained_bytes':sum(row['stdout']['byte_count']+row['stderr']['byte_count'] for row in items),'wall_seconds':1.0}
            docs['schema-manifest.json']=(r.encode(manifest)+'\n').encode()
            self.seal(receipt,docs);artifacts[receipt['artifact_name']]=docs
        return identity,artifacts

    def seal(self,receipt,docs):
        if 'schema-manifest.json' in docs:
            manifest=self.r.split71_json(docs['schema-manifest.json']);retained=0
            for item in manifest['items']:
                for stream in ('stdout','stderr'):
                    row=item[stream];raw=docs[row['file']];retained+=len(raw)
                    row.update(byte_count=len(raw),sha256=self.r.hashlib.sha256(raw).hexdigest());item['observed_bytes'][stream]=len(raw)
            manifest['retained_bytes']=retained;docs['schema-manifest.json']=(self.r.encode(manifest)+'\n').encode()
        receipt['evidence_sha256']={n:self.r.hashlib.sha256(v).hexdigest() for n,v in docs.items() if n!='receipt.json'}
        docs['receipt.json']=(self.r.encode(receipt)+'\n').encode()

    def change_receipt(self,docs,change):
        receipt=self.r.split71_json(docs['receipt.json']);change(receipt);self.seal(receipt,docs)

    def rejects(self,identity,artifacts,needs='success'):
        with self.assertRaises((ValueError,KeyError,TypeError)):
            self.r.aggregate_split71(self.selection,identity,artifacts,needs)

    def test_exact_two_partitions_union71_reparses_all_raw_results(self):
        identity,artifacts=self.fixture();result=self.r.aggregate_split71(self.selection,identity,artifacts,'success')
        self.assertEqual((result['actual_count'],result['counts']),(71,{'core':50,'app-unit':14,'ui':7}))
        self.assertEqual(len({row['method'] for row in result['actual']}),71)

    def test_every_new6_core_omission_rejected_even_after_rehash(self):
        self.assertEqual(len(runner.MERCHANT_METHODS),6)
        for method in runner.MERCHANT_METHODS:
            identity,artifacts=self.fixture();docs=next(iter(artifacts.values()))
            target,klass,name=method.split('/')
            docs['core.xml']=docs['core.xml'].replace(('<testcase classname="'+target+'.'+klass+'" name="'+name+'"/>').encode(),b'')
            docs['core-stdout.txt']=b'\n'.join(line for line in docs['core-stdout.txt'].splitlines() if (klass+' '+name+']').encode() not in line)
            self.seal(self.r.split71_json(docs['receipt.json']),docs);self.rejects(identity,artifacts)

    def test_legacy65_receipt_cannot_impersonate_split71(self):
        identity,artifacts=self.fixture();docs=next(iter(artifacts.values()))
        self.change_receipt(docs,lambda r:r.update(version=1,scope='selected-native-diagnostic-only',actual_count=65,expected_count=65))
        self.rejects(identity,artifacts)

    def test_missing_extra_duplicate_partition_and_wrong_artifact_names_rejected(self):
        for mode in ('missing','extra','wrong-name','duplicate-partition'):
            with self.subTest(mode=mode):
                identity,artifacts=self.fixture();first=next(iter(artifacts))
                if mode=='missing':artifacts.pop(first)
                elif mode=='extra':artifacts['alien']=artifacts[first]
                elif mode=='wrong-name':artifacts[first+'-other']=artifacts.pop(first)
                else:self.change_receipt(artifacts[first],lambda r:r.update(partition='ui-legacy'))
                self.rejects(identity,artifacts)

    def test_matrix_cancel_skip_failure_unknown_and_nonstring_success_rejected(self):
        for outcome in ('cancelled','skipped','failure','in_progress','',True,None):
            identity,artifacts=self.fixture();self.rejects(identity,artifacts,outcome)

    def test_cross_sha_run_attempt_tree_workflow_selection_and_repository_rejected(self):
        identity,original=self.fixture()
        for field in identity:
            with self.subTest(field=field):
                artifacts=copy.deepcopy(original);docs=next(iter(artifacts.values()))
                self.change_receipt(docs,lambda r:r.update({field:'wrong'}));self.rejects(identity,artifacts)

    def test_wrong_group_same_total_substitution_duplicate_and_zero_results_rejected(self):
        for mode in ('wrong-target','substitute','duplicate','zero'):
            identity,artifacts=self.fixture();docs=artifacts[self.r.split71_artifact_name(identity,'ui-legacy')]
            data=self.r.split71_json(docs['ui-tests.json']);nodes=data['testNodes'][0]['children']
            if mode=='wrong-target':data['testNodes'][0]['name']='QuestifyAppUnitTests'
            elif mode=='substitute':nodes[0]['nodeIdentifier']='QuestifyUITests/Other/testOther'
            elif mode=='duplicate':nodes[0]=copy.deepcopy(nodes[1])
            else:data['testNodes'][0]['children']=[]
            docs['ui-tests.json']=(self.r.encode(data)+'\n').encode();receipt=self.r.split71_json(docs['receipt.json']);self.seal(receipt,docs)
            self.rejects(identity,artifacts)

    def test_raw_json_tampering_and_rehashed_failure_skip_incomplete_rejected(self):
        for status in ('Failed','Skipped','Not Run','Unknown'):
            identity,artifacts=self.fixture();docs=artifacts[self.r.split71_artifact_name(identity,'ui-legacy')]
            data=self.r.split71_json(docs['ui-tests.json']);data['testNodes'][0]['children'][0]['result']=status
            docs['ui-tests.json']=(self.r.encode(data)+'\n').encode()
            self.rejects(identity,artifacts)
            self.seal(self.r.split71_json(docs['receipt.json']),docs);self.rejects(identity,artifacts)

    def test_nonzero_or_boolean_test_build_and_summary_counts_rejected(self):
        for value in (1,124,False,True,'0'):
            identity,artifacts=self.fixture();docs=next(iter(artifacts.values()))
            self.change_receipt(docs,lambda r:r['groups']['app-unit'].update(returncode=value));self.rejects(identity,artifacts)
        for field in ('totalTestCount','passedTests','failedTests','skippedTests','expectedFailures'):
            identity,artifacts=self.fixture();docs=next(iter(artifacts.values()))
            summary=self.r.split71_json(docs['app-unit-summary.json']);summary[field]=False
            docs['app-unit-summary.json']=(self.r.encode(summary)+'\n').encode();self.seal(self.r.split71_json(docs['receipt.json']),docs)
            self.rejects(identity,artifacts)
        identity,artifacts=self.fixture();docs=next(iter(artifacts.values()))
        phases=self.r.split71_json(docs['phase-times.json']);phases['app-build']['returncode']=1
        docs['phase-times.json']=(self.r.encode(phases)+'\n').encode();self.seal(self.r.split71_json(docs['receipt.json']),docs)
        self.rejects(identity,artifacts)

    def test_wrong_device_and_reused_device_toolchain_runtime_image_rejected(self):
        for mode in ('device','same-device','runtime','toolchain','image'):
            identity,artifacts=self.fixture();docs=artifacts[self.r.split71_artifact_name(identity,'ui-legacy')]
            receipt=self.r.split71_json(docs['receipt.json'])
            if mode=='device':receipt['simulator']['udid']='4'*8+'-'+'4'*4+'-'+'4'*4+'-'+'4'*4+'-'+'4'*12
            elif mode=='same-device':
                prior=self.r.split71_json(next(iter(artifacts.values()))['receipt.json']);receipt['simulator']['udid']=prior['simulator']['udid']
                summary=self.r.split71_json(docs['ui-summary.json']);summary['devicesAndConfigurations'][0]['device']['deviceId']=receipt['simulator']['udid'];docs['ui-summary.json']=(self.r.encode(summary)+'\n').encode()
            elif mode=='runtime':receipt['simulator']['runtime']='com.apple.CoreSimulator.SimRuntime.iOS-26-4'
            elif mode=='toolchain':receipt['toolchain']['swift']='other'
            else:receipt['runner_image']['ImageVersion']='other'
            self.seal(receipt,docs);self.rejects(identity,artifacts)

    def test_products_manifest_archive_and_before_after_changes_rejected(self):
        for mode in ('products','archive','manifest','before','after','source-after','configuration','ledger','xctestrun'):
            with self.subTest(mode=mode):
                identity,artifacts=self.fixture();docs=next(iter(artifacts.values()));receipt=self.r.split71_json(docs['receipt.json'])
                if mode=='products':receipt['products']={}
                elif mode=='archive':receipt['source_archive_sha256']='f'*64
                elif mode=='manifest':receipt['products']['app-unit']['manifest']['commit']='f'*40
                elif mode=='before':receipt['products_before']={}
                elif mode=='after':receipt['products_after']={}
                elif mode=='source-after':receipt['source_after']['source_tree']='f'*40
                elif mode=='configuration':receipt['products']['app-unit']['configuration']='Release/device'
                elif mode=='xctestrun':receipt['products']['app-unit']['xctestrun']='other.xctestrun'
                else:
                    ledger=self.r.split71_json(docs['products-ledger.json']);ledger['app-unit'][0][2]='0'*64;docs['products-ledger.json']=(self.r.encode(ledger)+'\n').encode()
                self.seal(receipt,docs);self.rejects(identity,artifacts)

    def test_unknown_missing_negative_nan_and_inconsistent_phase_rejected(self):
        for mode in ('unknown','missing','negative','nan','inconsistent','boolean'):
            identity,artifacts=self.fixture();docs=next(iter(artifacts.values()));phases=self.r.split71_json(docs['phase-times.json'])
            if mode=='unknown':phases['free-budget']=phases['boot']
            elif mode=='missing':phases.pop('python-validation')
            elif mode=='negative':phases['boot']['wall_seconds']=-1
            elif mode=='nan':phases['boot']['wall_seconds']=float('nan')
            elif mode=='boolean':phases['boot']['wall_seconds']=True
            else:phases['boot']['wall_seconds']=2
            docs['phase-times.json']=(self.r.encode(phases)+'\n').encode();self.seal(self.r.split71_json(docs['receipt.json']),docs)
            self.rejects(identity,artifacts)

    def test_current_selection_budget_partition_or_old_declaration_changes_rejected(self):
        for key,value in [('global_total',65),('global_counts',{'core':44,'app-unit':14,'ui':7}),('budget_seconds',{}),('admission','NOT_AUTHORIZED')]:
            selection=copy.deepcopy(self.selection);selection['merchant_readback']['split'][key]=value
            with self.assertRaises(ValueError):self.r.split71_layer(selection)
        old=self.r.merchant_test_preimage((MERCHANT_SOURCE/self.r.PATHS[3]).read_bytes())
        self.assertEqual(self.r.hashlib.sha256(old).hexdigest(),self.r.BYTEPERF_TEST_SHA256)

    def test_ui_raw_plist_must_match_product_inventory_and_safe_configuration(self):
        for mode in ('changed-bytes','live-api','wrong-platform','provisioned'):
            identity,artifacts=self.fixture();docs=artifacts[self.r.split71_artifact_name(identity,'ui-legacy')]
            receipt=self.r.split71_json(docs['receipt.json']);ledger=self.r.split71_json(docs['products-ledger.json'])
            info=plistlib.loads(docs['ui-info.plist'])
            if mode=='live-api':info['QuestifyAPIBaseURL']='https://live.invalid'
            elif mode=='wrong-platform':info['CFBundleSupportedPlatforms']=['iPhoneOS']
            elif mode=='changed-bytes':info['extra']='changed'
            else:ledger['ui'].append(['Debug-iphonesimulator/Questify.app/embedded.mobileprovision','file','f'*64])
            docs['ui-info.plist']=plistlib.dumps(info)
            if mode!='changed-bytes':
                for row in ledger['ui']:
                    if row[0].endswith('/Info.plist'):row[2]=self.r.hashlib.sha256(docs['ui-info.plist']).hexdigest()
                ledger['ui'].sort();product=receipt['products']['ui'];product.update(files=len(ledger['ui']),sha256=self.r.split71_hash(ledger['ui']))
                receipt['products_before']=copy.deepcopy(receipt['products']);receipt['products_after']=copy.deepcopy(receipt['products'])
                docs['products-ledger.json']=(self.r.encode(ledger)+'\n').encode()
            self.seal(receipt,docs);self.rejects(identity,artifacts)

    def test_device_schema_rejects_note_spoof_mixed_device_wrong_os_and_fabricated_runtime(self):
        for mode in ('note','mixed-device','wrong-os','runtime','tests-device','tests-configuration','unknown-schema'):
            with self.subTest(mode=mode):
                identity,artifacts=self.fixture();docs=artifacts[self.r.split71_artifact_name(identity,'ui-legacy')]
                receipt=self.r.split71_json(docs['receipt.json']);summary=self.r.split71_json(docs['ui-summary.json']);tests=self.r.split71_json(docs['ui-tests.json'])
                if mode=='note':
                    summary['devicesAndConfigurations'][0]['device']['deviceId']='foreign';summary['note']=receipt['simulator']['udid']
                elif mode=='mixed-device':summary['devicesAndConfigurations'].append(copy.deepcopy(summary['devicesAndConfigurations'][0]))
                elif mode=='wrong-os':summary['devicesAndConfigurations'][0]['device']['osVersion']='1.0'
                elif mode=='runtime':receipt['simulator']['runtime']='com.apple.CoreSimulator.SimRuntime.iOS-invented'
                elif mode=='tests-device':tests['devices'][0]['deviceId']='foreign'
                elif mode=='tests-configuration':tests['testPlanConfigurations'][0]['configurationId']='other'
                else:docs['xcresult-summary-help.txt']=b'unknown schema'
                docs['ui-summary.json']=(self.r.encode(summary)+'\n').encode();docs['ui-tests.json']=(self.r.encode(tests)+'\n').encode()
                self.seal(receipt,docs);self.rejects(identity,artifacts)

    def test_core_product_binary_ledger_mutation_is_rejected(self):
        identity,artifacts=self.fixture();docs=next(iter(artifacts.values()));ledger=self.r.split71_json(docs['products-ledger.json'])
        ledger['core'][0][2]='f'*64;docs['products-ledger.json']=(self.r.encode(ledger)+'\n').encode()
        self.seal(self.r.split71_json(docs['receipt.json']),docs);self.rejects(identity,artifacts)

    def test_fixed_history_read_is_bounded_sanitized_and_rejects_other_revision(self):
        r=self.r;root=MERCHANT_SOURCE;revision=next(iter(r.SPLIT71_PUBLIC_OBJECTS));tree=r.SPLIT71_PUBLIC_OBJECTS[revision]
        with mock.patch.object(r,'checked',side_effect=['',tree]),mock.patch.object(r,'execute') as execute:
            r.split71_ensure_public_object(root,revision);execute.assert_not_called()
        calls=[]
        def execute(command,where,timeout,capture=False,env=None):
            calls.append((command,timeout,env));return 0,b''
        with mock.patch.object(r,'checked',side_effect=[ValueError('missing'),'',tree]),mock.patch.object(r,'execute',side_effect=execute):
            r.split71_ensure_public_object(root,revision)
        command,timeout,environment=calls[-1]
        self.assertEqual(timeout,60);self.assertEqual(command[-2:],['https://github.com/liboyang42-cpu/chengyin-ios.git',revision])
        self.assertEqual(environment['HOME'],'/dev/null');self.assertEqual(environment['GIT_CONFIG_GLOBAL'],'/dev/null')
        self.assertFalse(any(k in environment for k in ('GIT_CONFIG_COUNT','HTTPS_PROXY','GITHUB_TOKEN','SSH_AUTH_SOCK')))
        self.assertIn('http.followRedirects=false',command);self.assertIn('--depth=1',command)
        with self.assertRaises(ValueError):r.split71_ensure_public_object(root,'0'*40)
        with mock.patch.object(r,'checked',side_effect=ValueError('missing')),mock.patch.object(r,'execute',return_value=(0,b'http.extraheader\n')),self.assertRaises(ValueError):
            r.split71_ensure_public_object(root,revision)

    def test_summary_overall_failure_or_nonempty_failure_list_rejected_after_rehash(self):
        for field,value in [('result','Failed'),('result','Unknown'),('result',None),('testFailures',[{'failureText':'contradictory'}])]:
            identity,artifacts=self.fixture();docs=artifacts[self.r.split71_artifact_name(identity,'ui-legacy')]
            summary=self.r.split71_json(docs['ui-summary.json']);summary[field]=value
            docs['ui-summary.json']=(self.r.encode(summary)+'\n').encode();self.seal(self.r.split71_json(docs['receipt.json']),docs)
            self.rejects(identity,artifacts)

    def test_worker_clock_cannot_hide_overhead_overlap_or_exceed_worker_cap(self):
        for mode in ('overhead','overlap','cap'):
            identity,artifacts=self.fixture();docs=next(iter(artifacts.values()));receipt=self.r.split71_json(docs['receipt.json'])
            phases=self.r.split71_json(docs['phase-times.json'])
            if mode=='overhead':receipt['worker_clock']['unclassified_overhead_seconds']=-1
            elif mode=='overlap':
                phases['boot']=dict(phases['app-test']);receipt['worker_clock']=self.r.split71_worker_clock(phases)
            else:
                phases['report']['ended_monotonic']+=3000;phases['report']['wall_seconds']+=3000;receipt['worker_clock']=self.r.split71_worker_clock(phases)
            docs['phase-times.json']=(self.r.encode(phases)+'\n').encode();self.seal(receipt,docs);self.rejects(identity,artifacts)

    def test_fixed_two_worker_authorization_does_not_admit_changed_contract(self):
        self.r.split71_require_admission(self.selection)
        selection=copy.deepcopy(self.selection);selection['merchant_readback']['split']['peak_macos_jobs']=3
        with self.assertRaises(ValueError):self.r.split71_require_admission(selection)

    def test_method_commands_have_only_exact_whole_identities_and_original_timeouts(self):
        for part in self.r.SPLIT71_PARTITIONS:
            for group in self.r.split71_groups(self.selection,part):
                if group['kind']=='swift':continue
                command=self.r.xcode_test_command(group,Path('/products/run.xctestrun'),'a',Path('/results'))
                self.assertEqual([x[14:] for x in command if x.startswith('-only-testing:')],group['methods'])
                self.assertEqual(command[command.index('-maximum-test-execution-time-allowance')+1],'120' if group['name']=='app-unit' else '900')
        budget=self.selection['merchant_readback']['split']['budget_seconds'];self.assertEqual(budget['ui-legacy-test'],1000);self.assertEqual(budget['app-test'],360)

    def test_evidence_allowlist_refuses_symlinks_extra_products_and_duplicate_json_keys(self):
        identity,artifacts=self.fixture();docs=next(iter(artifacts.values()))
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name,raw in docs.items():(root/name).write_bytes(raw)
            self.assertEqual(self.r.split71_read_evidence(root,'core-app'),docs)
            (root/'Questify.app').mkdir()
            with self.assertRaises(ValueError):self.r.split71_read_evidence(root,'core-app')
            (root/'Questify.app').rmdir();(root/'core.xml').unlink();(root/'core.xml').symlink_to(root/'receipt.json')
            with self.assertRaises(ValueError):self.r.split71_read_evidence(root,'core-app')
        with self.assertRaises(ValueError):self.r.split71_json(b'{"a":1,"a":2}')

    def test_current_workflow_uses_fixed_matrix_bounded_same_attempt_artifacts_and_no_permissions_expansion(self):
        raw=(MERCHANT_SOURCE/'.github/workflows/native-targeted.yml').read_text()
        for text in ('partition: [core-app, ui-legacy]','fail-fast: false','max-parallel: 2','continue-on-error: false','needs: [targeted]','if: always()','retention-days: 1','overwrite: false','merge-multiple: false','fetch-depth: 2','persist-credentials: false','contents: read'):
            self.assertIn(text,raw)
        self.assertIn('native-targeted-71-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}-',raw)
        for text in ('permissions: write','id-token:','secrets.','token:','continue-on-error: true','merge-multiple: true'):
            self.assertNotIn(text,raw)


    def test_split_acquisition_requires_only_its_seven_exact_raw_commands_and_keeps_unsupported_bytes(self):
        for partition in self.r.SPLIT71_PARTITIONS:
            with self.subTest(partition=partition),tempfile.TemporaryDirectory() as tmp:
                output=Path(tmp);group='app-unit' if partition=='core-app' else 'ui';result=output/(group+'.xcresult');result.mkdir()
                calls=[];raw=b'  UNSUPPORTED RAW SCHEMA\n\x00\xff'
                def capture(command,root,seconds,limit):
                    calls.append((command,seconds,limit))
                    return {'argv':command,'status':'CAPTURED','returncode':0,'wall_seconds':0.0,'observed_bytes':{'stdout':len(raw),'stderr':0},'truncated':{'stdout':False,'stderr':False},'stdout':raw,'stderr':b''}
                with mock.patch.object(self.r,'merchant_capture_command',side_effect=capture):
                    manifest=self.r.split71_capture_schema(output,output,partition,{group:result},{})
                self.assertEqual(manifest['status'],'CAPTURED');self.assertIs(manifest['native_test_result_authority'],False)
                self.assertEqual(len(calls),7);self.assertTrue(all(0<row[1]<=30 for row in calls))
                names=[r[0] for r in self.r.split71_schema_rows(partition,result)]
                self.assertEqual([r['file'] for r in manifest['items']],names)
                self.assertEqual({p.name for p in (output/'schema-evidence').iterdir()},set(names)|{n+'.stderr.txt' for n in names}|{'manifest.json'})
                self.assertEqual((output/'schema-evidence'/'xcresult-summary-help.txt').read_bytes(),raw)
                self.assertNotIn('ui-' if group=='app-unit' else 'app-unit-',' '.join(names))

    def test_split_acquisition_manifest_rejects_failure_timeout_truncation_identity_path_and_scope_even_after_rehash(self):
        for mode in ('failure','timeout','truncation','nonzero','boolean','identity','partition','path','extra','missing','total-time','item-time','budget','authority'):
            with self.subTest(mode=mode):
                identity,artifacts=self.fixture();docs=next(iter(artifacts.values()));receipt=self.r.split71_json(docs['receipt.json'])
                manifest=self.r.split71_json(docs['schema-manifest.json'])
                if mode=='failure':manifest['status']='PARTIAL_OR_FAILED'
                elif mode=='timeout':manifest['items'][0]['status']='TIMEOUT'
                elif mode=='truncation':manifest['items'][0]['truncated']['stdout']=True
                elif mode=='nonzero':manifest['items'][0]['returncode']=1
                elif mode=='boolean':manifest['items'][0]['returncode']=False
                elif mode=='identity':manifest['identity']['run_attempt']='1'
                elif mode=='partition':manifest['partition']='ui-legacy'
                elif mode=='path':manifest['result_bundle_path']='/foreign/ui.xcresult'
                elif mode=='extra':manifest['items'].append(copy.deepcopy(manifest['items'][0]))
                elif mode=='missing':manifest['items'].pop()
                elif mode=='total-time':manifest['wall_seconds']=91
                elif mode=='item-time':manifest['items'][0]['wall_seconds']=31
                elif mode=='budget':manifest['limits']['total_seconds']=100
                else:manifest['native_test_result_authority']=True
                docs['schema-manifest.json']=(self.r.encode(manifest)+'\n').encode();self.seal(receipt,docs)
                self.rejects(identity,artifacts)

    def test_split_acquisition_missing_bundle_expired_budget_and_aliased_path_never_become_complete(self):
        for mode in ('missing','expired','link','foreign'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as tmp:
                output=Path(tmp);result=output/'app-unit.xcresult'
                if mode!='missing':result.mkdir()
                if mode=='link':
                    real=output/'real.xcresult';result.rename(real);result.symlink_to(real,target_is_directory=True)
                if mode=='foreign':result=output/'foreign'/'app-unit.xcresult';result.mkdir(parents=True)
                def capture(command,root,seconds,limit):
                    return {'argv':command,'status':'CAPTURED','returncode':0,'wall_seconds':0.0,'observed_bytes':{'stdout':2,'stderr':0},'truncated':{'stdout':False,'stderr':False},'stdout':b'{}','stderr':b''}
                with mock.patch.object(self.r,'merchant_capture_command',side_effect=capture) as call:
                    manifest=self.r.split71_capture_schema(output,output,'core-app',{'app-unit':result},{},seconds=0 if mode=='expired' else 90)
                self.assertEqual(manifest['status'],'PARTIAL_OR_FAILED')
                self.assertEqual(call.call_count,0 if mode=='expired' else 5)
                self.assertTrue(all(item['status']=='NOT_RUN' for item in manifest['items'][-2:]))

    def test_split_test_execution_cannot_mark_pass_before_actual_schema_admission(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp);preflight=output/'preflight.json'
            phases={name:{'started_monotonic':1.0,'ended_monotonic':2.0,'wall_seconds':1.0,'returncode':0} for name in ('checkout-initialization','python-validation','source-validation')}
            self.r.write_json(preflight,phases)
            job=self.r.Split71Diagnostic(MERCHANT_SOURCE,output,self.selection,'ui-legacy',preflight)
            group=self.r.split71_groups(self.selection,'ui-legacy')[0];result=output/'ui.xcresult'
            command=self.r.xcode_test_command(group,Path('/synthetic/run.xctestrun'),'fixture',result)
            with mock.patch.object(job,'command',return_value=(0,b'')):
                job.collect(group,command,1000,result)
            self.assertEqual(job.receipt['groups']['ui']['status'],'EXECUTED_UNVALIDATED')
            self.assertEqual(job.receipt['groups']['ui']['actual_count'],0)
            self.assertEqual(job.receipt['status'],'INCOMPLETE')
            self.assertEqual(job.schema_result_paths,{'ui':result})
            with mock.patch.object(job,'execute_partition',side_effect=KeyboardInterrupt),mock.patch.object(job,'capture_schema') as capture,self.assertRaises(KeyboardInterrupt):job.run()
            capture.assert_not_called()
            with mock.patch.object(job,'execute_partition',side_effect=ValueError('unauthenticated')),mock.patch.object(job,'capture_schema') as capture,self.assertRaises(ValueError):job.run()
            capture.assert_not_called()

    def report_fixture(self):
        identity,artifacts=self.fixture();partition='ui-legacy';docs=artifacts[self.r.split71_artifact_name(identity,partition)]
        temporary=tempfile.TemporaryDirectory();self.addCleanup(temporary.cleanup);root=Path(temporary.name)
        output=root/'output';output.mkdir();capture=output/'schema-evidence';capture.mkdir();result=output/'ui.xcresult';result.mkdir()
        receipt=self.r.split71_json(docs['receipt.json']);receipt.update(status='EXECUTED',result_bundle_path=str(result))
        manifest=self.r.split71_json(docs['schema-manifest.json']);manifest['result_bundle_path']=str(result)
        commands={name:command for name,command,_ in self.r.split71_schema_rows(partition,result)}
        for item in manifest['items']:item['argv']=commands[item['file']]
        docs['schema-manifest.json']=(self.r.encode(manifest)+'\n').encode()
        phases=self.r.split71_json(docs['phase-times.json']);shift=self.r.time.monotonic()-100
        for phase in phases.values():phase['started_monotonic']+=shift;phase['ended_monotonic']+=shift
        phases.pop('report');docs['phase-times.json']=(self.r.encode(phases)+'\n').encode()
        self.seal(receipt,docs)
        capture_names={r[0] for r in self.r.split71_schema_rows(partition,result)}
        capture_names|={n+'.stderr.txt' for n in tuple(capture_names)}
        for name,raw in docs.items():
            if name=='schema-manifest.json':(capture/'manifest.json').write_bytes(raw)
            elif name in capture_names:(capture/name).write_bytes(raw)
            else:(output/name).write_bytes(raw)
        return identity,output,root/'evidence',docs

    def test_unknown_raw_help_is_retained_but_no_pass_evidence_is_written(self):
        identity,output,evidence,docs=self.report_fixture()
        manifest=self.r.split71_json((output/'schema-evidence'/'manifest.json').read_bytes())
        raw=b'RAW CURRENT APPLE TOOL HELP: unsupported\n'
        (output/'schema-evidence'/'xcresult-summary-help.txt').write_bytes(raw)
        row=next(r for r in manifest['items'] if r['file']=='xcresult-summary-help.txt')
        old=row['stdout']['byte_count'];row['stdout'].update(byte_count=len(raw),sha256=self.r.hashlib.sha256(raw).hexdigest());row['observed_bytes']['stdout']=len(raw)
        manifest['retained_bytes']+=len(raw)-old;self.r.write_json(output/'schema-evidence'/'manifest.json',manifest)
        with mock.patch.object(self.r,'split71_identity',return_value=identity),mock.patch.object(self.r,'merchant_capture_command') as command,self.assertRaisesRegex(ValueError,'Unknown xcresulttool schema-help format'):
            self.r.split71_report(output,evidence,self.selection,MERCHANT_SOURCE)
        command.assert_not_called();self.assertFalse(evidence.exists())
        self.assertEqual((output/'schema-evidence'/'xcresult-summary-help.txt').read_bytes(),raw)
        self.assertEqual(self.r.read_json(output/'receipt.json')['status'],'EXECUTED')

    def test_report_reextracts_both_current_result_documents_before_pass_and_rejects_changed_result(self):
        for changed in (False,True):
            with self.subTest(changed=changed):
                identity,output,evidence,docs=self.report_fixture();calls=[]
                def capture(command,root,seconds,limit):
                    calls.append(command);kind=command[4];raw=docs['ui-'+kind+'.json']
                    if changed and kind=='tests':raw=b'{}'
                    return {'status':'CAPTURED','returncode':0,'stdout':raw}
                with mock.patch.object(self.r,'split71_identity',return_value=identity),mock.patch.object(self.r,'merchant_capture_command',side_effect=capture):
                    if changed:
                        with self.assertRaisesRegex(ValueError,'Re-extracted xcresult differs'):self.r.split71_report(output,evidence,self.selection,MERCHANT_SOURCE)
                        self.assertFalse(evidence.exists())
                    else:
                        self.r.split71_report(output,evidence,self.selection,MERCHANT_SOURCE)
                        actual=self.r.split71_read_evidence(evidence,'ui-legacy');receipt=self.r.split71_json(actual['receipt.json'])
                        self.assertEqual(len(self.r.validate_split71_partition(receipt,identity,self.selection,actual)),7)
                self.assertEqual([c[4] for c in calls],['summary','tests'])

# MERCHANT_READBACK_TESTS_END


# CREATOR_FIXTURE_TESTS_BEGIN
FIXTURE276_IDENTITIES = ('SelectionAndCommands.test_actual_bound_source_and_all_65_declarations', 'SelectionAndCommands.test_original_29_methods_are_preserved_and_only_16_added', 'SelectionAndCommands.test_per_method_source_binding_rejects_missing_swapped_duplicate_and_wrong_target', 'SelectionAndCommands.test_repinned_changed_method_and_duplicate_source_declaration_fail', 'SelectionAndCommands.test_duplicate_declaration_is_not_a_unique_method', 'SelectionAndCommands.test_nonboolean_version_and_exact_contract', 'SelectionAndCommands.test_changed_source_hash_and_missing_guard_rejected', 'SelectionAndCommands.test_empty_duplicate_target_and_wildcard_selectors_rejected', 'SelectionAndCommands.test_core_filter_is_exact_set_without_full_suite_fallback', 'SelectionAndCommands.test_every_xcode_method_has_its_own_exact_filter', 'SelectionAndCommands.test_workflow_remains_additive_standard_and_independent', 'SelectionAndCommands.test_original_gates_project_schemes_and_product_sources_are_unchanged', 'ReviewedCompileRepair.test_complete_predecessors_and_unrelated_contract_semantics_are_preserved', 'ReviewedCompileRepair.test_real_central_projection_accepts_current_support_and_exact_inverse', 'ReviewedCompileRepair.test_repair_inverse_rejects_off_hunk_changes_even_with_rehashed_postimage', 'Results.test_xunit_reads_all_forty_four_real_cases', 'Results.test_core_transcript_proves_execution_beyond_swiftpm_xunit', 'Results.test_xunit_failures_skips_and_unknown_status_cannot_pass', 'Results.test_modern_xcresult_exact_target_and_method_set', 'Results.test_xcresult_missing_wrong_target_bad_identifier_and_unknown_schema', 'Results.test_target_url_binding_must_not_override_wrong_bundle', 'Results.test_zero_omitted_extra_duplicate_failed_skipped_timeout_and_cancel_fail', 'Results.test_hidden_repetitions_and_xunit_summary_disagreement_fail', 'Results.test_summary_counts_actual_device_and_no_boolean_counts', 'RuntimeBoundaries.test_single_installed_iphone_and_no_automatic_other_device', 'RuntimeBoundaries.test_run_requires_hosted_mac_exact_repo_branch_and_event', 'RuntimeBoundaries.test_process_exit_is_real_and_timeout_never_passes', 'RuntimeBoundaries.test_core_build_is_once_before_exact_execution_and_failure_stops', 'RuntimeBoundaries.test_core_capture_keeps_stderr_live_and_limits_only_evidence', 'RuntimeBoundaries.test_every_cleanup_wait_is_bounded_even_after_kill', 'RuntimeBoundaries.test_product_target_selection_supports_only_safe_testhost_tokens', 'RuntimeBoundaries.test_product_directory_alias_returns_canonical_safe_run', 'RuntimeBoundaries.test_ambiguous_products_and_extra_target_fail', 'RuntimeBoundaries.test_inventory_detects_product_mutation_and_escaping_links', 'RuntimeBoundaries.test_scope_requires_exact_sha_base_and_nineteen_exact_statuses', 'RuntimeBoundaries.test_duplicate_json_keys_rejected', 'RuntimeBoundaries.test_missing_receipt_reports_not_run', 'ReceiptIdentity.test_exact_same_run_sha_tree_configuration_and_65_results', 'ReceiptIdentity.test_report_revalidates_real_exported_files_not_just_receipt_counts', 'ReceiptIdentity.test_other_run_attempt_sha_tree_selection_or_workflow_rejected', 'ReceiptIdentity.test_missing_or_wrong_configuration_toolchain_simulator_or_group_rejected', 'CreatorCurrentTreeAndCounts.test_every_creator_current_tree_mode_blob_and_presence_is_exact', 'CreatorCurrentTreeAndCounts.test_receipt_counts_are_real_integers_and_outer_fields_are_exact', 'Creator65Contract.test_original_45_exact_bindings_plus_independent_20_are_exactly_65', 'Creator65Contract.test_each_of_the_65_methods_has_one_declaration_in_its_exact_source', 'Creator65Contract.test_each_new_method_rejects_repinned_replacement_or_wrong_source', 'Creator65Contract.test_each_new_declaration_is_checked_before_creator_image_validation', 'Creator65Contract.test_new_source_binding_cannot_be_dropped_even_after_outer_repin', 'Creator65Contract.test_core_44_requires_both_complete_independent_execution_streams', 'Creator65Contract.test_old_45_receipt_cannot_be_upgraded_by_renaming_or_recounting', 'Creator65Contract.test_each_new_method_is_required_in_the_65_receipt', 'Creator65Contract.test_creator_15_and_diagnostic_4_have_exact_independent_statuses', 'Creator65Contract.test_all_creator_current_bytes_sha_and_git_blobs_are_independently_bound', 'Creator65Contract.test_creator_missing_duplicate_reordered_and_changed_rows_reject_outer_repin', 'Creator65Contract.test_every_creator_path_rejects_changed_real_current_bytes', 'Creator65Contract.test_added_files_cannot_be_rehashed_or_claim_predecessors_or_hunks', 'Creator65Contract.test_modified_creator_inverse_requires_complete_predecessor', 'Creator65Contract.test_creator_baseline_requires_each_modified_blob_and_all_four_additions_absent', 'Creator65Contract.test_each_creator_current_sha_and_blob_check_remains_active_after_inner_repin', 'Creator65Contract.test_each_creator_current_file_must_exist_as_a_regular_checkout_file', 'Creator65Contract.test_added_file_null_predecessor_and_empty_hunks_are_independently_enforced', 'ShallowCheckoutBoundaries.test_current_bytes_validate_without_history_but_real_run_scope_requires_it', 'ShallowCheckoutBoundaries.test_real_git_witness_proves_predecessors_and_addition_absence_without_parent_history', 'StaticRepairBinding.test_exact_published_base_nine_paths_and_old_domains_remain_separate', 'StaticRepairBinding.test_complete_current_payload_inverts_to_independent_b75_bytes', 'StaticRepairBinding.test_manifest_cannot_widen_or_change_under_outer_repin', 'StaticRepairBinding.test_every_payload_checks_real_bytes_sha_blob_and_regular_file', 'StaticRepairBinding.test_inverse_rejects_rehashed_off_hunk_and_fabricated_addition_predecessors', 'StaticRepairBinding.test_actual_parent_nine_path_scope_and_receipt_cannot_claim_old_scope', 'StaticRepairBinding.test_each_baseline_and_current_tree_mode_blob_and_addition_absence', 'StaticRepairBinding.test_real_git_subset_witness_binds_b75_payload_and_current_mode_blobs', 'PublishedParentBridge.test_exact_eight_path_parent_bridge_preserves_old_source_domains', 'PublishedParentBridge.test_current_to_true_parent_to_b75_inverses_match_every_historical_source', 'PublishedParentBridge.test_parent_bridge_rejects_repinned_missing_reordered_or_expanded_inputs', 'PublishedParentBridge.test_each_parent_inverse_rejects_rehashed_off_hunk_and_changed_real_sources', 'PublishedParentBridge.test_every_real_parent_bridge_tree_mode_blob_and_presence_is_exact', 'PublishedParentBridge.test_parent_history_and_receipts_cannot_relabel_b75_as_current_parent', 'FixedPublicCreatorRead.test_present_exact_object_never_fetches_or_inspects_network_configuration', 'FixedPublicCreatorRead.test_missing_object_uses_one_whitelisted_bounded_noninteractive_public_read', 'FixedPublicCreatorRead.test_offline_timeout_or_unreadable_config_fail_closed_without_retry', 'FixedPublicCreatorRead.test_existing_or_fetched_wrong_tree_parent_or_duplicate_parent_is_rejected', 'FixedPublicCreatorRead.test_credential_redirect_include_and_auth_configuration_never_reach_fetch', 'FixedPublicCreatorRead.test_public_target_cannot_be_generalized_by_changing_fixed_identity', 'NativeC2afBoundary.test_original83_complete_method_sources_are_unchanged', 'NativeC2afBoundary.test_new14_old15_history34_history19_and_original65_remain_separate', 'NativeC2afBoundary.test_all_eleven_physical_postimages_restore_exact_complete_c2af_sources', 'NativeC2afBoundary.test_no_v5_missing_unknown_or_expanded_current_layer_is_accepted', 'NativeC2afBoundary.test_rehashed_rows_cannot_change_independent_predecessors_or_inverse_shape', 'NativeC2afBoundary.test_each_current_source_rejects_missing_alias_stale_bytes_and_same_stat_mutation', 'NativeC2afBoundary.test_navigation_crlf_cr_and_rehashed_off_hunk_changes_fail_complete_inverse', 'NativeC2afBoundary.test_incomplete_or_forged_predecessor_maps_cannot_feed_historical_checks', 'NativeC2afBoundary.test_native_receipt_requires_current_c2af_layer_before_original65_receipt_checks', 'NativeC2afBoundary.test_all_fourteen_actual_tree_modes_blobs_and_presence_are_mandatory', 'NativeC2afBoundary.test_exact_scope_rejects_wrong_or_missing_parent_and_each_historical_layer', 'NativeC2afBoundary.test_real_git_subset_tree_witness_is_separate_from_mocked_scope_transport', 'FixedPublicRepairRead.test_present_exact_3393_never_fetches', 'FixedPublicRepairRead.test_missing_3393_uses_only_separate_fixed_public_bounded_fetch', 'FixedPublicRepairRead.test_3393_network_failures_and_credential_configuration_refuse_without_retry', 'FixedPublicRepairRead.test_3393_fixed_identity_wrong_tree_parent_merge_and_missing_headers_fail', 'PortableDiagnosticBoundary.test_complete_original83_sources_reject_body_decorator_comment_missing_duplicate_and_line_endings', 'PortableDiagnosticBoundary.test_exact_f04_selection_source_and_four_path_layer_are_mandatory', 'PortableDiagnosticBoundary.test_all_four_actual_current_files_and_both_tree_authorities_are_strict', 'PortableDiagnosticBoundary.test_entry_test_inverse_preserves_exact_f04_and_rejects_old_current_or_off_hunk', 'PortableDiagnosticBoundary.test_new4_and_published14_15_34_19_scope_cannot_be_relabelled', 'PortableDiagnosticBoundary.test_portable_receipt_requires_new_identity_before_original65_checks', 'FixedPublicNativeRead.test_present_c2af_never_fetches', 'FixedPublicNativeRead.test_missing_c2af_is_one_exact_bounded_public_read', 'FixedPublicNativeRead.test_bad_c2af_identity_config_timeout_and_parent_fail_closed', 'DescriptionRepairBoundary.test_complete_original108_methods_and_decorators_are_byte_identical', 'DescriptionRepairBoundary.test_original108_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'DescriptionRepairBoundary.test_new11_old4_native14_15_34_19_and_original65_stay_separate', 'DescriptionRepairBoundary.test_all_eight_current_payloads_restore_exact_complete_7b_bytes', 'DescriptionRepairBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'DescriptionRepairBoundary.test_each_of_eleven_current_files_rejects_missing_old_and_same_stat_bytes', 'DescriptionRepairBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'DescriptionRepairBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'DescriptionRepairBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'DescriptionRepairBoundary.test_every_before_and_current_tree_requires_all_eleven_exact_modes_blobs_and_types', 'DescriptionRepairBoundary.test_new11_scope_authenticates_old4_native14_and_all_older_domains', 'DescriptionRepairBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'DescriptionRepairBoundary.test_description_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'FixedPublicPortableRead.test_present_exact_f04_never_fetches_or_reads_network_configuration', 'FixedPublicPortableRead.test_missing_f04_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPortableRead.test_f04_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPortableRead.test_f04_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPortableRead.test_existing_or_fetched_f04_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPortableRead.test_fixed_f04_public_object_identity_cannot_be_generalized', 'SocialActorBoundary.test_complete_original127_methods_and_decorators_are_byte_identical', 'SocialActorBoundary.test_original127_binding_rejects_body_decorator_comment_omission_duplicates_and_newlines', 'SocialActorBoundary.test_new15_old11_old4_native14_15_34_19_and_original65_stay_separate', 'SocialActorBoundary.test_all_twelve_current_payloads_restore_exact_complete_42_bytes', 'SocialActorBoundary.test_selection_missing_unknown_reordered_and_historical_layers_fail', 'SocialActorBoundary.test_each_of_fifteen_current_files_rejects_missing_old_and_same_stat_bytes', 'SocialActorBoundary.test_leaf_and_ancestor_symbolic_links_inside_or_outside_root_are_rejected', 'SocialActorBoundary.test_each_payload_rejects_coherently_repinned_off_hunk_postimage', 'SocialActorBoundary.test_inverse_predecessor_hash_blob_hunks_and_complete_path_set_are_independent', 'SocialActorBoundary.test_every_before_and_current_tree_requires_all_fifteen_exact_modes_blobs_and_types', 'SocialActorBoundary.test_new15_scope_authenticates_old11_old4_native14_and_all_older_domains', 'SocialActorBoundary.test_scope_rejects_wrong_parent_extra_parent_modes_each_history_and_dirty_checkout', 'SocialActorBoundary.test_social_receipt_requires_new_identity_and_still_requires_all65_actual_results', 'SocialActorBoundary.test_actor_leaf_is_only_initializer_annotation_and_equatable_identity_bytes_are_unchanged', 'SocialActorBoundary.test_merchant_single_test_leaf_matches_reviewed_complete_after_and_exact42_before', 'SocialActorBoundary.test_historical_inputs_copy_bytes_without_aliasing_any_current_checkout_file', 'SocialActorBoundary.test_new_performance_control_cannot_claim_any_historical_predecessor', 'FixedPublicDescriptionRead.test_present_exact_7b_never_fetches_or_reads_network_configuration', 'FixedPublicDescriptionRead.test_missing_7b_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicDescriptionRead.test_7b_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicDescriptionRead.test_7b_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicDescriptionRead.test_existing_or_fetched_7b_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicDescriptionRead.test_fixed_7b_public_object_identity_cannot_be_generalized', 'PathTemplateDiagnosticBoundary.test_original150_complete_method_bytes_and_decorators_are_unchanged', 'PathTemplateDiagnosticBoundary.test_original150_source_identity_rejects_body_comment_missing_and_duplicate_method', 'PathTemplateDiagnosticBoundary.test_complete_bb5_predecessor_json_and_test_bytes_are_fixed', 'PathTemplateDiagnosticBoundary.test_all_three_current_raw_files_reject_missing_old_same_size_mtime_and_links_after_warm', 'PathTemplateDiagnosticBoundary.test_noncanonical_selection_bytes_and_unknown_or_missing_layer_are_rejected', 'PathTemplateDiagnosticBoundary.test_missing_foreign_source_never_falls_back_to_loaded_healthy_root', 'PathTemplateDiagnosticBoundary.test_parent_directory_symlink_is_rejected_even_for_byte_identical_inputs', 'PathTemplateDiagnosticBoundary.test_historical_fixture_has_no_hardlink_into_real_current_source', 'PathTemplateDiagnosticBoundary.test_coherent_outer_repin_cannot_change_before_blobs_or_any_historical_selection_byte', 'PathTemplateDiagnosticBoundary.test_exact_new3_scope_preserves_all_published_fifteen_and_older_layers', 'PathTemplateDiagnosticBoundary.test_scope_rejects_new_parent_merge_mode_missing_extra_and_every_old_scope', 'PathTemplateDiagnosticBoundary.test_receipt_requires_pathfix_and_every_old_identity_and_all65_real_results', 'XctestrunPathTemplateTests.test_plain_and_double_underscore_product_root_aliases', 'XctestrunPathTemplateTests.test_literal_token_product_roots_are_not_reexpanded', 'XctestrunPathTemplateTests.test_double_underscore_product_children_and_absolute_paths', 'XctestrunPathTemplateTests.test_nested_host_tokens_preserve_literal_physical_root_names', 'XctestrunPathTemplateTests.test_unknown_template_tokens_reject_existing_literal_paths', 'XctestrunPathTemplateTests.test_missing_empty_and_recursive_host_tokens_reject', 'XctestrunPathTemplateTests.test_relative_and_missing_product_fields_reject', 'XctestrunPathTemplateTests.test_parent_and_absolute_sibling_escapes_reject', 'XctestrunPathTemplateTests.test_product_links_stay_inside_root_and_run_links_reject', 'XctestrunPathTemplateTests.test_multiple_runs_extra_targets_and_no_match_reject', 'XctestrunPathTemplateTests.test_non_token_double_underscore_names_remain_literal', 'FixedPublicSocialRead.test_present_exact_42_never_fetches_or_reads_network_configuration', 'FixedPublicSocialRead.test_missing_42_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicSocialRead.test_42_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicSocialRead.test_42_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicSocialRead.test_existing_or_fetched_42_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicSocialRead.test_fixed_42_public_object_identity_cannot_be_generalized', 'AlbumGetterActorBoundary.test_all179_previously_reviewed_method_bytes_remain_exact', 'AlbumGetterActorBoundary.test_exact_eight_payloads_restore_bb5_and_keep_all_other_files_out', 'AlbumGetterActorBoundary.test_only_actor_annotation_changes_and_all_nine_swift_methods_stay_intact', 'AlbumGetterActorBoundary.test_payload_rows_cannot_omit_duplicate_reorder_or_coherently_replace_preimages', 'CasefoldFixtureBoundary.test_all183_complete_method_bytes_decorators_and_comments_remain_unchanged', 'CasefoldFixtureBoundary.test_actual_identical_and_case_variant_names_have_independent_parents', 'CasefoldFixtureBoundary.test_simulated_casefold_directory_collision_rejects_old_layout_not_isolated_helper', 'CasefoldFixtureBoundary.test_selector_complete_function_and_original_literal_cases_remain_fixed', 'CasefoldFixtureBoundary.test_current_three_raw_missing_old_same_stat_symlink_and_foreign_root_rejected', 'CasefoldFixtureBoundary.test_exact_raw_json_and_coherent_before_repin_cannot_forge_predecessor', 'CasefoldFixtureBoundary.test_published54_complete_before_images_and_old_domain_do_not_admit_new_layer', 'CasefoldFixtureBoundary.test_bounded_published54_fixture_never_hardlinks_current_sources', 'CasefoldFixtureBoundary.test_receipt_requires_new_identity_every_old_layer_and_all65_actual_methods', 'FixedPublicPathfixRead.test_present_exact_bb5_never_fetches_or_reads_network_configuration', 'FixedPublicPathfixRead.test_missing_bb5_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicPathfixRead.test_bb5_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicPathfixRead.test_bb5_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicPathfixRead.test_existing_or_fetched_bb5_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicPathfixRead.test_fixed_bb5_public_object_identity_cannot_be_generalized', 'BoundedByteTransformBoundary.test_complete_original198_methods_are_preserved_without_weakened_assertions', 'BoundedByteTransformBoundary.test_warm_boundaries_reject_each_current_raw_same_size_mtime_missing_and_symlink', 'BoundedByteTransformBoundary.test_all_five_source_inverses_restore_complete_published_c3a_bytes', 'BoundedByteTransformBoundary.test_old_defaults_reject_new_layer_and_mixed_foreign_current_roots', 'BoundedByteTransformBoundary.test_exact_raw_selection_and_inverse_payload_cannot_be_coherently_rebound', 'BoundedByteTransformBoundary.test_warm_async_and_threaded_boundary_still_reads_actual_root_bytes', 'BoundedByteTransformBoundary.test_bounded_physical_predecessors_share_no_inodes', 'BoundedByteTransformBoundary.test_receipt_requires_all_new_and_old_identity_fields', 'FixedPublicCasefoldRead.test_present_exact_54f_never_fetches_or_reads_network_configuration', 'FixedPublicCasefoldRead.test_missing_54f_uses_one_exact_bounded_noninteractive_public_read_without_credentials', 'FixedPublicCasefoldRead.test_54f_credential_redirect_include_and_auth_configuration_fail_before_fetch', 'FixedPublicCasefoldRead.test_54f_unreadable_config_offline_and_timeout_fail_closed_without_retry', 'FixedPublicCasefoldRead.test_existing_or_fetched_54f_wrong_tree_parent_merge_or_missing_headers_fail', 'FixedPublicCasefoldRead.test_fixed_54f_public_object_identity_cannot_be_generalized', 'MerchantReadbackBoundary.test_original212_complete_methods_and_full_predecessor_files_are_exact', 'MerchantReadbackBoundary.test_exact_current71_retains_all65_and_six_real_new_source_bindings', 'MerchantReadbackBoundary.test_old_defaults_reject_current71_and_current_rejects_old65', 'MerchantReadbackBoundary.test_each_new_method_missing_duplicate_extra_wrong_source_and_old_recount_reject', 'MerchantReadbackBoundary.test_warm_current_six_reject_same_stat_missing_symlink_and_hardlink_aliases', 'MerchantReadbackBoundary.test_root_and_ancestor_links_and_noncanonical_json_fail', 'MerchantReadbackBoundary.test_projection_is_explicit_readonly_same_root_and_reauthenticates_after_warm', 'MerchantReadbackBoundary.test_coherent_payload_repin_cannot_replace_complete_predecessor_or_frozen_postimage', 'MerchantReadbackBoundary.test_current_core_filter_selects_all50_and_each_new_method_exactly', 'MerchantReadbackBoundary.test_core50_requires_both_real_streams_and_every_new_method', 'MerchantReadbackBoundary.test_current71_receipt_rejects_old65_missing_each_new_and_forged_counter', 'MerchantReadbackBoundary.test_receipt_preserves_every_historical_identity_and_result_digest_requirement', 'MerchantReadbackBoundary.test_current_receipt_initialization_is71_and_legacy_initialization_stays65', 'MerchantReadbackBoundary.test_each_before_and_after_tree_path_mode_type_blob_and_addition_absence', 'MerchantReadbackBoundary.test_scope_exact_six_full_trees_githubsha_parent_and_dirty_guards', 'MerchantReadbackBoundary.test_missing_real_parent_fails_without_fetch_or_alternate_object_acquisition', 'MerchantReadbackBoundary.test_report_missing_receipt_stays_not_run_without_scope_or_execution', 'MerchantReadbackBoundary.test_report_revalidates_current50_xml_transcript_and_every_exported_result', 'MerchantReadbackBoundary.test_published7bf_nine_path_bridge_reaches_exact_c3_history_without_network', 'MerchantReadbackBoundary.test_published_bridge_rejects_wrong_headers_diff_every_mode_blob_and_old_chain', 'MerchantReadbackBoundary.test_present_commit_missing_tree_stops_before_any_legacy_fetch_helper', 'MerchantReadbackBoundary.test_complete_tree_reconstruction_authenticates_empty_trees_and_directory_modes', 'MerchantReadbackBoundary.test_cli_alias_source_root_is_rejected_before_normalizing_it_away', 'MerchantReadbackBoundary.test_c3_present_never_fetches_and_fixed_target_cannot_be_generalized', 'MerchantReadbackBoundary.test_c3_missing_commit_or_tree_fetches_one_exact_public_object_with_safe_environment', 'MerchantReadbackBoundary.test_c3_unsafe_configuration_stops_before_fetch', 'MerchantReadbackBoundary.test_c3_config_network_timeout_and_success_without_objects_fail_without_retry', 'MerchantReadbackBoundary.test_c3_wrong_tree_parent_merge_duplicate_or_missing_headers_are_rejected', 'MerchantReadbackBoundary.test_schema_commands_use_exact_observed_result_paths_and_nine_bounded_reads', 'MerchantReadbackBoundary.test_schema_without_actual_result_is_not_run_and_never_invents_a_default_path', 'MerchantReadbackBoundary.test_schema_raw_bytes_metadata_and_receipt_authority_stay_separate', 'MerchantReadbackBoundary.test_schema_time_budget_missing_results_links_and_command_failures_are_explicit', 'MerchantReadbackBoundary.test_schema_streaming_limits_and_timeout_are_real_local_process_controls', 'MerchantReadbackBoundary.test_schema_capture_never_rewrites_test_status_and_respects_cancellation', 'MerchantReadbackBoundary.test_schema_workflow_is_exact_split_allowlist_and_old_no_artifact_domain_restored', 'Split71PartitionProtocol.test_exact_two_partitions_union71_reparses_all_raw_results', 'Split71PartitionProtocol.test_every_new6_core_omission_rejected_even_after_rehash', 'Split71PartitionProtocol.test_legacy65_receipt_cannot_impersonate_split71', 'Split71PartitionProtocol.test_missing_extra_duplicate_partition_and_wrong_artifact_names_rejected', 'Split71PartitionProtocol.test_matrix_cancel_skip_failure_unknown_and_nonstring_success_rejected', 'Split71PartitionProtocol.test_cross_sha_run_attempt_tree_workflow_selection_and_repository_rejected', 'Split71PartitionProtocol.test_wrong_group_same_total_substitution_duplicate_and_zero_results_rejected', 'Split71PartitionProtocol.test_raw_json_tampering_and_rehashed_failure_skip_incomplete_rejected', 'Split71PartitionProtocol.test_nonzero_or_boolean_test_build_and_summary_counts_rejected', 'Split71PartitionProtocol.test_wrong_device_and_reused_device_toolchain_runtime_image_rejected', 'Split71PartitionProtocol.test_products_manifest_archive_and_before_after_changes_rejected', 'Split71PartitionProtocol.test_unknown_missing_negative_nan_and_inconsistent_phase_rejected', 'Split71PartitionProtocol.test_current_selection_budget_partition_or_old_declaration_changes_rejected', 'Split71PartitionProtocol.test_ui_raw_plist_must_match_product_inventory_and_safe_configuration', 'Split71PartitionProtocol.test_device_schema_rejects_note_spoof_mixed_device_wrong_os_and_fabricated_runtime', 'Split71PartitionProtocol.test_core_product_binary_ledger_mutation_is_rejected', 'Split71PartitionProtocol.test_fixed_history_read_is_bounded_sanitized_and_rejects_other_revision', 'Split71PartitionProtocol.test_summary_overall_failure_or_nonempty_failure_list_rejected_after_rehash', 'Split71PartitionProtocol.test_worker_clock_cannot_hide_overhead_overlap_or_exceed_worker_cap', 'Split71PartitionProtocol.test_fixed_two_worker_authorization_does_not_admit_changed_contract', 'Split71PartitionProtocol.test_method_commands_have_only_exact_whole_identities_and_original_timeouts', 'Split71PartitionProtocol.test_evidence_allowlist_refuses_symlinks_extra_products_and_duplicate_json_keys', 'Split71PartitionProtocol.test_current_workflow_uses_fixed_matrix_bounded_same_attempt_artifacts_and_no_permissions_expansion', 'Split71PartitionProtocol.test_split_acquisition_requires_only_its_seven_exact_raw_commands_and_keeps_unsupported_bytes', 'Split71PartitionProtocol.test_split_acquisition_manifest_rejects_failure_timeout_truncation_identity_path_and_scope_even_after_rehash', 'Split71PartitionProtocol.test_split_acquisition_missing_bundle_expired_budget_and_aliased_path_never_become_complete', 'Split71PartitionProtocol.test_split_test_execution_cannot_mark_pass_before_actual_schema_admission', 'Split71PartitionProtocol.test_unknown_raw_help_is_retained_but_no_pass_evidence_is_written', 'Split71PartitionProtocol.test_report_reextracts_both_current_result_documents_before_pass_and_rejects_changed_result')
FIXTURE276_SOURCE_SHA256 = '03cb72c651440a7b9cf0809fe1da9c7eb3851d6306121d33357939d9f969ac7e'
class CreatorFixtureDiagnosticBoundary(unittest.TestCase):
    r = FIXTURE_RUNNER

    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='fixture-nine-control-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve(strict=True)
        paths = {p.relative_to(FIXTURE_PARENT_SOURCE).as_posix() for p in FIXTURE_PARENT_SOURCE.rglob('*') if p.is_file()}
        paths.update(self.r.FIXTURE_PATHS)
        for relative in sorted(paths):
            source = FIXTURE_SOURCE / relative
            self.assertTrue(source.is_file())
            self.assertFalse(source.is_symlink())
            target = root / relative; target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        return root

    def test_current_nine_and_unchanged71_partition_contract(self):
        self.r.validate_split71_selection(FIXTURE_SELECTION, FIXTURE_SOURCE)
        self.assertEqual(self.r.split71_layer(FIXTURE_SELECTION), runner.split71_layer(MERCHANT_SELECTION))
        self.assertEqual(FIXTURE_SELECTION['groups'], MERCHANT_SELECTION['groups'])
        self.assertEqual([len(p['methods']) for p in self.r.split71_layer(FIXTURE_SELECTION)['partitions']], [64, 7])

    def test_complete_parent_diagnostic_and_source_preimages_match_real_git(self):
        restored = self.r.fixture_predecessor_sources(FIXTURE_SELECTION, FIXTURE_SOURCE)
        self.assertEqual(len(restored), 8)
        for relative, raw in restored.items():
            with self.subTest(path=relative):
                expected = subprocess.check_output(['git', '-C', str(FIXTURE_SOURCE), 'show', self.r.FIXTURE_BASE_COMMIT + ':' + relative])
                self.assertEqual(raw, expected)
                self.assertEqual((FIXTURE_PARENT_SOURCE / relative).read_bytes(), expected)
        self.assertNotIn('tools/tests/test_creator_history_fixture_rejection.py', restored)
        self.assertEqual(runner.NATIVE_IMPLEMENTATION_SHA256, self.r.FIXTURE_BEFORE[self.r.PATHS[2]]['sha256'])

    def test_original276_methods_and_complete_parent_test_source_preserved(self):
        raw = self.r.fixture_test_preimage((FIXTURE_SOURCE / self.r.PATHS[3]).read_bytes())
        lines = raw.splitlines(True); found = {}
        for cls in ast.parse(raw).body:
            if isinstance(cls, ast.ClassDef):
                for node in cls.body:
                    if isinstance(node, ast.FunctionDef) and node.name.startswith('test_'):
                        start = min([node.lineno] + [d.lineno for d in node.decorator_list])
                        found[cls.name + '.' + node.name] = b''.join(lines[start - 1:node.end_lineno]).decode()
        self.assertEqual(tuple(found), FIXTURE276_IDENTITIES)
        self.assertEqual(len(found), 276)
        self.assertEqual(self.r.hashlib.sha256(self.r.encode(found).encode()).hexdigest(), FIXTURE276_SOURCE_SHA256)
        current = ast.parse((FIXTURE_SOURCE / self.r.PATHS[3]).read_text()); current_lines = (FIXTURE_SOURCE / self.r.PATHS[3]).read_text().splitlines(True)
        for cls in current.body:
            if isinstance(cls, ast.ClassDef):
                for node in cls.body:
                    key = cls.name + '.' + getattr(node, 'name', '')
                    if key in found:
                        start = min([node.lineno] + [d.lineno for d in node.decorator_list])
                        self.assertEqual(''.join(current_lines[start - 1:node.end_lineno]), found[key])

    def test_each_complete_nine_input_hot_mutation_and_restoration(self):
        root = self.fixture(); self.r.fixture_current_inputs(FIXTURE_SELECTION, root)
        for relative in self.r.FIXTURE_PATHS:
            with self.subTest(path=relative):
                path = root / relative; raw = path.read_bytes(); stat = path.stat()
                changed = bytes([raw[0] ^ 1]) + raw[1:]; path.write_bytes(changed)
                os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
                with self.assertRaises(ValueError): self.r.fixture_current_inputs(FIXTURE_SELECTION, root)
                path.write_bytes(raw)
        self.r.fixture_current_inputs(FIXTURE_SELECTION, root)

    def test_each_nine_missing_and_alias_rejected(self):
        root = self.fixture()
        for relative in self.r.FIXTURE_PATHS:
            with self.subTest(path=relative):
                path = root / relative; raw = path.read_bytes(); path.unlink()
                with self.assertRaises(ValueError): self.r.fixture_current_inputs(FIXTURE_SELECTION, root)
                other = root / 'alias-source'; other.write_bytes(raw); path.symlink_to(other)
                with self.assertRaises(ValueError): self.r.fixture_current_inputs(FIXTURE_SELECTION, root)
                path.unlink(); os.link(other, path)
                with self.assertRaises(ValueError): self.r.fixture_current_inputs(FIXTURE_SELECTION, root)
                path.unlink(); other.unlink(); path.write_bytes(raw)

    def test_old_default_admission_stays_closed_to_current_sources(self):
        with self.assertRaises(ValueError): self.r.validate_merchant_selection(MERCHANT_SELECTION, FIXTURE_SOURCE)
        with self.assertRaises(ValueError): self.r.fixture_current_inputs(MERCHANT_SELECTION, FIXTURE_SOURCE)
        changed = copy.deepcopy(FIXTURE_SELECTION); changed['creator_fixture_rejection']['payload'][0]['after_sha256'] = '0' * 64
        with self.assertRaises(ValueError): self.r.fixture_predecessor_selection(changed)
        changed = copy.deepcopy(FIXTURE_SELECTION); changed['groups'][0]['methods'].pop()
        with self.assertRaises(ValueError): self.r.split71_layer(changed)

    def test_explicit_history_view_reauthenticates_current_source_without_acceptance_cache(self):
        root = self.fixture()
        old = self.r.fixture_predecessor_selection(FIXTURE_SELECTION)
        view = self.r.merchant_history_root(old, root, fixture_layer=True)
        relative = 'tools/run138_editor_readiness.py'; path = root / relative
        expected = (FIXTURE_PARENT_SOURCE / relative).read_bytes()
        self.assertEqual((view / relative).read_bytes(), expected)
        raw = path.read_bytes(); stat = path.stat(); path.write_bytes(raw[:-1] + bytes([raw[-1] ^ 1]))
        os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        with self.assertRaises(ValueError): (view / relative).read_bytes()
        path.write_bytes(raw)
        self.assertEqual((view / relative).read_bytes(), expected)
        with self.assertRaises(ValueError): (view / relative).open('wb')

    def test_fixed_public7bf_fetch_has_bounded_credentialfree_target(self):
        calls = []
        def checked(command, root):
            if command[:3] == ['git', 'cat-file', '-e'] and not calls: raise ValueError('missing')
            if command[:3] == ['git', 'cat-file', '-p']:
                return 'tree ' + self.r.MERCHANT_BASE_TREE + '\nparent ' + self.r.BYTEPERF_BASE_COMMIT + '\n\nfixed'
            return ''
        def execute(command, root, seconds, *args, **kwargs):
            calls.append((command, seconds, kwargs))
            return 0, b''
        with mock.patch.object(self.r, 'checked', side_effect=checked), mock.patch.object(self.r, 'execute', side_effect=execute):
            self.r.ensure_fixture_7bf_commit(FIXTURE_SOURCE)
        self.assertEqual(len(calls), 2)
        command, seconds, kw = calls[1]
        self.assertEqual(command[-2:], ['https://github.com/liboyang42-cpu/chengyin-ios.git', self.r.MERCHANT_BASE_COMMIT])
        self.assertEqual(seconds, 60)
        self.assertIn('http.followRedirects=false', command)
        self.assertIn('credential.helper=', command)
        self.assertEqual(kw['env']['GIT_TERMINAL_PROMPT'], '0')
        self.assertEqual(kw['env']['GIT_CONFIG_GLOBAL'], '/dev/null')

    def test_scope_dispatch_remains_explicit_and_result_schema_unchanged(self):
        identity = {'source_sha': 'a' * 40, 'source_tree': 'b' * 40, 'fixture_base_commit': self.r.FIXTURE_BASE_COMMIT}
        with mock.patch.object(self.r, 'validate_split71_selection'), mock.patch.object(self.r, 'split71_ensure_public_object'), mock.patch.object(self.r, 'verify_fixture_scope', return_value=identity) as current, mock.patch.object(self.r, 'verify_merchant_scope', side_effect=AssertionError('old scope')):
            self.assertEqual(self.r.verify_split71_scope(FIXTURE_SOURCE, FIXTURE_SELECTION), {'source_sha': 'a' * 40, 'source_tree': 'b' * 40})
            current.assert_called_once_with(FIXTURE_SOURCE, FIXTURE_SELECTION)

    def test_merchant_positive_fixture_canonicalizes_real_ancestor_alias_without_weakening_source_guard(self):
        # A real local filesystem alias reproduces macOS-style temporary-root
        # ancestry. It is not a claim about the unprinted CI temporary pathname.
        with tempfile.TemporaryDirectory(prefix='merchant-fixture-alias-control-') as directory:
            outer = Path(directory).resolve(strict=True)
            physical = outer / 'physical'; physical.mkdir()
            alias = outer / 'alias'; alias.symlink_to(physical, target_is_directory=True)
            helper = MerchantReadbackBoundary()
            try:
                with mock.patch.object(tempfile, 'tempdir', str(alias)):
                    canonical = helper.fixture()
                self.assertEqual(canonical, canonical.resolve(strict=True))
                self.assertTrue(canonical.is_relative_to(physical))
                # Use the same authenticated historical runner/source domain as
                # MerchantReadbackBoundary, never a current-layer bypass.
                historical_runner = helper.fixture.__globals__['runner']
                historical_selection = helper.fixture.__globals__['MERCHANT_SELECTION']
                historical_runner.merchant_current_inputs(historical_selection, canonical)
                ancestor_alias = alias / canonical.relative_to(physical)
                self.assertTrue(ancestor_alias.is_dir())
                self.assertFalse(ancestor_alias.is_symlink())
                with self.assertRaisesRegex(ValueError, 'Merchant source root contains an alias'):
                    historical_runner.merchant_current_inputs(historical_selection, ancestor_alias)
                leaf_alias = outer / 'root-alias'; leaf_alias.symlink_to(canonical, target_is_directory=True)
                with self.assertRaisesRegex(ValueError, 'real checkout directory'):
                    historical_runner.merchant_current_inputs(historical_selection, leaf_alias)
            finally:
                helper.doCleanups()
    def test_coherent_user_repin_of_added_control_remains_rejected(self):
        root = self.fixture()
        path = root / 'tools/tests/test_creator_history_fixture_rejection.py'
        path.write_bytes(path.read_bytes() + b'\n# coordinated repin\n')
        changed = copy.deepcopy(FIXTURE_SELECTION)
        row = next(r for r in changed['creator_fixture_rejection']['payload'] if r['path'] == path.relative_to(root).as_posix())
        row['after_sha256'] = self.r.hashlib.sha256(path.read_bytes()).hexdigest()
        row['after_blob'] = self.r.blob_id(path.read_bytes())
        (root / self.r.PATHS[1]).write_text(json.dumps(changed, indent=2, ensure_ascii=True) + '\n')
        with self.assertRaises(ValueError): self.r.fixture_current_inputs(changed, root)
        with self.assertRaises(ValueError): self.r.validate_split71_selection(changed, root)

    def test_current_external_root_aliases_never_normalized(self):
        root = self.fixture()
        with tempfile.TemporaryDirectory(prefix='fixture-current-alias-') as directory:
            physical = Path(directory).resolve(strict=True)
            alias = physical / 'alias'; alias.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'real checkout directory'):
                self.r.fixture_current_inputs(FIXTURE_SELECTION, alias)
            alias.unlink(); alias.symlink_to(root.parent, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'contains an alias'):
                self.r.fixture_current_inputs(FIXTURE_SELECTION, alias / root.name)

    def test_fixed_public_fetch_rejects_credential_configuration_and_wrong_history(self):
        with mock.patch.object(self.r, 'checked', side_effect=ValueError('missing')), mock.patch.object(self.r, 'execute', return_value=(0, b'http.extraheader\n')) as execute:
            with self.assertRaisesRegex(ValueError, 'credential, redirect'):
                self.r.ensure_fixture_7bf_commit(FIXTURE_SOURCE)
            self.assertEqual(execute.call_count, 1)
        with mock.patch.object(self.r, 'checked', return_value='tree ' + self.r.MERCHANT_BASE_TREE + '\nparent ' + '0' * 40 + '\n\nwrong'), mock.patch.object(self.r, 'execute', side_effect=AssertionError('no fetch')):
            with self.assertRaisesRegex(ValueError, 'commit/tree/parent identity differs'):
                self.r.ensure_fixture_7bf_commit(FIXTURE_SOURCE)
    def test_current_selection_receipts_bind_new_identity_and_preserve_exact71_results(self):
        helper = Split71PartitionProtocol(); helper.r = self.r; helper.selection = FIXTURE_SELECTION
        identity, artifacts = helper.fixture()
        identity['selection_sha256'] = self.r.FIXTURE_SELECTION_RAW_SHA256
        with self.assertRaises(ValueError): self.r.aggregate_split71(FIXTURE_SELECTION, identity, artifacts, 'success')
        for docs in artifacts.values():
            receipt = self.r.split71_json(docs['receipt.json'])
            receipt['selection_sha256'] = identity['selection_sha256']
            schema = self.r.split71_json(docs['schema-manifest.json'])
            schema['identity']['selection_sha256'] = identity['selection_sha256']
            docs['schema-manifest.json'] = (self.r.encode(schema) + '\n').encode()
            helper.seal(receipt, docs)
        result = self.r.aggregate_split71(FIXTURE_SELECTION, identity, artifacts, 'success')
        self.assertEqual((result['actual_count'], result['counts']), (71, {'core': 50, 'app-unit': 14, 'ui': 7}))
        self.assertEqual(len({row['method'] for row in result['actual']}), 71)
        changed = copy.deepcopy(artifacts)
        docs = next(iter(changed.values()))
        helper.change_receipt(docs, lambda receipt: receipt.update(selection_sha256=runner.MERCHANT_SELECTION_RAW_SHA256))
        with self.assertRaises(ValueError): self.r.aggregate_split71(FIXTURE_SELECTION, identity, changed, 'success')
    def test_mutation_between_preimage_authentication_and_view_hash_binding_rejects(self):
        root = self.fixture(); target = root / 'tools/run138_editor_readiness.py'
        raw = target.read_bytes(); original = self.r.fixture_predecessor_sources; calls = []
        def mutate_after_authenticated_preimage(selection, source):
            restored = original(selection, source); calls.append(1)
            if len(calls) == 2:
                stat = target.stat()
                target.write_bytes(raw[:-1] + bytes([raw[-1] ^ 1]))
                os.utime(target, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            return restored
        with mock.patch.object(self.r, 'fixture_predecessor_sources', side_effect=mutate_after_authenticated_preimage):
            with self.assertRaisesRegex(ValueError, 'Changed frozen fixture postimage'):
                self.r.merchant_history_root(MERCHANT_SELECTION, root, fixture_layer=True)
        self.assertEqual(len(calls), 2)
        target.write_bytes(raw)
        view = self.r.merchant_history_root(MERCHANT_SELECTION, root, fixture_layer=True)
        self.assertEqual((view / 'tools/run138_editor_readiness.py').read_bytes(),
                         (FIXTURE_PARENT_SOURCE / 'tools/run138_editor_readiness.py').read_bytes())
# CREATOR_FIXTURE_TESTS_END
if __name__ == '__main__':
    unittest.main()
