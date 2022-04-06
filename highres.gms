******************************************
* highres main script
******************************************

* $ontext
option profile=1
* $offtext
option limrow=0, limcol=0, solprint=OFF
option decimals = 4
$offlisting
$ONMULTI
$ONEPS
$offdigit

* Switches:

* log = text file to store details about model run time, optimality or not, etc.
* gdx2sql (ON/OFF) = whether to convert output GDX to sqlite database -> easier to read into Python
* storage (ON/OFF) = should storage be included in the model run
* hydrores (ON/OFF) = should reservoir hydro be incliuded in the model run
* UC (ON/OFF) = unit committment switch
* f_res (ON/OFF) = should frequency response requirements be modelled
* water (ON/OFF) = model technologies with a water footprint (currently disabled)
* sensitivity (ON/OFF) = whether a sensitivity file is available
* GWatts (YES/NO) = model is run in GW (YES) or MW (NO)

* sense_run = sensitivity file identifier
* esys_scen = energy system scenario (sets the carbon budget and demands to be used)
* psys_scen = power system scenario (sets which technologies are available)
* RPS = renewable portfolio standard
* vre_restrict = VRE land use deployment scenario name
* model_yr = which year in the future are we modelling
* weather_yr = which weather year do we use
* dem_yr = which demand year do we use

* fx_trans (YES/NO) = fix transmission network to input values
* fx_natcap (YES/NO) = fix total national capacities ->  let highRES decide where to place them
* nz_trans (YES/NO) = force net zero electricity trade balance between UK and Europe over the year
* pen_gen (ON/OFF) = weather VoLL is modelled
* fx_caps_to = file containing capacities to fix the system to

* outname = output name of GDX file


$setglobal log "test_log"
$setglobal gdx2sql "OFF"
$setglobal cplex_opt_file "1"

$setglobal storage "ON"
$setglobal hydrores "ON"
$setglobal UC "ON"
$setglobal f_res "ON"

$setglobal water "OFF"
$setglobal sensitivity "ON"

$setglobal GWatts "YES"

$setglobal sense_run "MedREMedNuc"
$setglobal esys_scen "BASE"
$setglobal psys_scen "BASE"
$setglobal RPS "optimal"
$setglobal vre_restrict ""
$setglobal model_yr "2050"
$setglobal weather_yr "2010"
$setglobal dem_yr "2010"
$setglobal fx_trans "YES"
$setglobal fx_natcap "NO"
$setglobal nz_trans "NO"
$set pen_gen "OFF"

$setglobal fx_caps_to ""

$setglobal outname "dev_2010"


$setglobal store_uc "OFF"

**************************************************


* rescale from MW to GW for better numerics (allegedly)

scalar MWtoGW;

$ifThen "%GWatts%" == YES

MWtoGW=1E3;

$else

MWtoGW=1;

$endif

$INCLUDE highres_data_input.gms

* sets to dermine which zones are in the UK and which aren't

set uk_z(z) / UK1*UK9 /;
set uk_z_alias(z_alias) / UK1*UK9 /;
set not_uk_z_alias(z_alias);

not_uk_z_alias(z_alias)$(not uk_z(z_alias)) = YES;

*set dem(g) / SynCon2/;




$IF "%storage%" == ON $INCLUDE highres_storage_setup.gms

* WARNING: for parameter updates to work there can be no arithmetic in the code
* before the update is run -> sensitivity data must be imported here


$IF "%sensitivity%" == ON $INCLUDE sensitivity_%sense_run%.dd

* if no RPS set just do an optimal run

$IF "%RPS%" == "optimal" $GOTO optimal1

scalar
RPS
/%RPS%/
;
RPS=RPS/100.

$label optimal1

scalar
emis_price
/0./
;


demand(z,h)=demand(z,h)/MWtoGW;
gen_cap2area(vre)=gen_cap2area(vre)/MWtoGW;
trans_links_cap(z,z_alias,trans)=trans_links_cap(z,z_alias,trans)/MWtoGW;
gen_unitsize(non_vre)=gen_unitsize(non_vre)/MWtoGW;
gen_maxramp(non_vre)=gen_maxramp(non_vre)/MWtoGW;




* Existing VRE capacity aggregated to zones

exist_vre_cap_r(vre,z,r) = 0.0;

$ontext
gen_exist_pcap_z(z,vre,"FX")=sum(r,exist_vre_cap_r(vre,z,r));

$offtext

* Existing zonal capacity aggregated to national

parameter gen_exist_cap(g);
gen_exist_cap(g)=sum((z,lt),gen_exist_pcap_z(z,g,lt));

* Limit which regions a given VRE tech can be built in
* based on buildable area in that region. Stops offshore solar
* and onshore offshore wind.

set vre_lim(vre,z,r);
vre_lim(vre,z,r)=((area(vre,z,r)+exist_vre_cap_r(vre,z,r))>0.);

* Non VRE cap lim to dynamic set, stops Nuclear being built in London

set gen_lim(z,g);
gen_lim(z,non_vre)=((sum(lt,gen_lim_pcap_z(z,non_vre,lt))+sum(lt,gen_exist_pcap_z(z,non_vre,lt)))>0.);
gen_lim(z,vre)=(sum(r,(area(vre,z,r)+exist_vre_cap_r(vre,z,r)))>0.);


sets
gen_lin(z,non_vre)
ramp_on(z,non_vre)
mingen_on(z,non_vre)
ramp_and_mingen(z,non_vre)
;



$ifThen "%UC%" == ON

*set gen_uc_lin(non_vre);
*set gen_uc_int(non_vre);

* set for generations that can provide quick start operating reserve

set gen_quick(non_vre);

* which zones have UC constraints turned on - here only turned on for UK zones

set uc_z(z) /UK1*UK9/;

* only OCGT can provide quick start reserves

gen_quick("NaturalgasOCGTnew")=YES;

* generators that are represented as continous linear capacity chunks

gen_lin(z,non_vre)=not ((gen_uc_lin(non_vre) or gen_uc_int(non_vre)) and uc_z(z));

* generators that are continous linear chunks can have a mingen of 0

parameter gen_mingen_lin(non_vre);
gen_mingen_lin(non_vre)=0.;

$else

*if UC is not on all generators are linear chunks

gen_lin(z,non_vre)=YES;

parameter gen_mingen_lin(non_vre);
gen_mingen_lin(non_vre)=gen_mingen(non_vre);
gen_mingen_lin("NaturalgasOCGTnew")=0.0;
gen_mingen_lin("NaturalgasCCGTwithCCSnewOT")=0.0;

$endIf

* Sets to ensure ramp/mingen constraints are only created where relevant

ramp_on(z,non_vre)=((gen_maxramp(non_vre)*60./gen_unitsize(non_vre)) < 1.0 and gen_lim(z,non_vre) and gen_lin(z,non_vre) and gen_unitsize(non_vre) > 0.);

mingen_on(z,non_vre)=(gen_mingen_lin(non_vre) > 0. and gen_lim(z,non_vre) and gen_lin(z,non_vre));

ramp_and_mingen(z,non_vre) = (ramp_on(z,non_vre) or mingen_on(z,non_vre));

* Buildable area per cell from km2 to MW power capacity

area(vre,z,r)=area(vre,z,r)$(vre_lim(vre,z,r))*gen_cap2area(vre);

* To be conservative, existing capacity is removed from new capacity limit

area(vre,z,r)=area(vre,z,r)-exist_vre_cap_r(vre,z,r);
area(vre,z,r)$(area(vre,z,r)<0.) = 0.  ;

* Fuel, varom and emission costs for non VRE gens;

gen_varom(non_vre)=gen_fuelcost(non_vre)+gen_emisfac(non_vre)*emis_price+gen_varom(non_vre);


* Penalty generation setup
* VoLL set at 6000�/MWh

scalar
pgen /6./;


* Solar marginal

gen_varom("Solar")=0.001;

*trans_varom(trans)=0.001;

* Rescale parameters for runs that are greater or less than one year

if (card(h) < 8760,
co2_budget=round(co2_budget*(card(h)/8760.),8);
gen_capex(g)=round(gen_capex(g)*(card(h)/8760.),8);
gen_fom(g)=round(gen_fom(g)*(card(h)/8760.),8);
trans_line_capex(trans)=round(trans_line_capex(trans)*(card(h)/8760.),8);
trans_sub_capex(trans)=round(trans_sub_capex(trans)*(card(h)/8760.),8);

store_fom(s)=round(store_fom(s)*(card(h)/8760.),8);
store_pcapex(s)=round(store_pcapex(s)*(card(h)/8760.),8);
store_ecapex(s)=round(store_ecapex(s)*(card(h)/8760.),8);
*store_e_unitcapex(s)=round(store_e_unitcapex(s)*(card(h)/8760.),8);
);




Variables
costs                                    total electricty system costs

* Total cost components

costs_gen_capex(z)
costs_gen_fom(z)
costs_gen_varom(z)
$IF "%UC%" == ON costs_gen_start(z)
costs_store_capex(z)
costs_store_fom(z)
costs_store_varom(z)
$IF "%store_uc%" == ON costs_store_start(z)
costs_trans_capex(z)
costs_trans_fom(z)

Positive variables
var_new_pcap(g)                          new generation capacity at national level
var_new_pcap_z(z,g)                      new generation capacity at zonal level
var_exist_pcap(g)                        existing generation capacity at national level
var_exist_pcap_z(z,g)                    existing generation capacity at zonal level
var_tot_pcap(g)                          total generation capacity at national level
var_tot_pcap_z(z,g)                      total generation capacity at zonal level
var_gen(h,z,g)                           generation by hour and technology
var_new_vre_pcap_r(z,vre,r)              new VRE capacity at grid cell level by technology and zone
var_exist_vre_pcap_r(z,vre,r)            existing VRE capacity at grid cell level by technology and zone
var_vre_gen_r(h,z,vre,r)                 VRE generation at grid cell level by hour zone and technology
var_vre_curtail(h,z,vre,r)               VRE power curtailed
*var_non_vre_curtail(z,h,non_vre)
var_trans_flow(h,z,z_alias,trans)        Flow of electricity from node to node by hour (MW)
var_trans_pcap(z,z_alias,trans)          Capacity of node to node transmission links (MW)

var_pgen(h,z)                            Penalty generation

;

* Synchronous condensers can have negative generation - they require energy to function

var_gen.LO(h,z,"SynCon")=-inf;

*** Transmission set up ***

* Sets up bidirectionality of links

trans_links(z_alias,z,trans)$(trans_links(z,z_alias,trans))=trans_links(z,z_alias,trans);

trans_links_cap(z_alias,z,trans)$(trans_links_cap(z,z_alias,trans) > 0.)=trans_links_cap(z,z_alias,trans);

trans_links_dist(z,z_alias,trans)=trans_links_dist(z,z_alias,trans)/100.;

* Bidirectionality of link distances for import flow reduction -> both monodir and bidir needed,
* former for capex.

parameter trans_links_dist_bidir(z,z_alias,trans);

trans_links_dist_bidir(z,z_alias,trans)=trans_links_dist(z,z_alias,trans);
trans_links_dist_bidir(z_alias,z,trans)$(trans_links_dist(z,z_alias,trans) > 0.)=trans_links_dist(z,z_alias,trans);

* Set transmission capacities to historic

$ifThen "%fx_trans%" == "YES"

var_trans_pcap.FX(z,z_alias,trans)$(trans_links(z,z_alias,trans) and not_uk_z_alias(z_alias)) = trans_links_cap(z,z_alias,trans);

$else

* Or limit all links to some maximum

var_trans_pcap.UP(z,z_alias,trans)$(trans_links(z,z_alias,trans))=50.;

$endIf



*******************************

var_exist_pcap_z.UP(z,g)$(gen_exist_pcap_z(z,g,"UP")) = gen_exist_pcap_z(z,g,"UP");
*var_exist_pcap_z.L(z,g)$(gen_exist_pcap_z(z,g,"UP")) = gen_exist_pcap_z(z,g,"UP");

var_exist_pcap_z.LO(z,g)$(gen_exist_pcap_z(z,g,"LO")) = gen_exist_pcap_z(z,g,"LO");
var_exist_pcap_z.FX(z,g)$(gen_exist_pcap_z(z,g,"FX")) = gen_exist_pcap_z(z,g,"FX");

var_exist_pcap_z.UP(z,g)$(not (sum(lt,gen_exist_pcap_z(z,g,lt)) > 0.)) = 0.0;


var_tot_pcap_z.UP(z,g)$(gen_lim_pcap_z(z,g,'UP'))=gen_lim_pcap_z(z,g,'UP');
var_tot_pcap_z.LO(z,g)$(gen_lim_pcap_z(z,g,'LO'))=gen_lim_pcap_z(z,g,'LO');
var_tot_pcap_z.FX(z,g)$(gen_lim_pcap_z(z,g,'FX'))=gen_lim_pcap_z(z,g,'FX');


*var_vre_pcap_r.LO(z,vre,r)$(exist_vre_cap_r(vre,z,r))=exist_vre_cap_r(vre,z,r);

$IF "%fx_natcap%" == YES var_new_pcap.FX(g)$(gen_fx_natcap(g))=gen_fx_natcap(g);



$ifThen "%UC%" == ON

* parameters for UC, used by both gen and storage UC so needs to be defined here

scalars
f_res_time                               frequency response ramp up window (minutes)                             /0.083/
res_time                                 operating reserve ramp up window (minutes)                              /20./
unit_cap_lim_z                           limit the maximum capacity of each units deployed in each zone (MW)     /50000./
res_margin                               operating reserve margin (fraction of demand)                           / 0.1 /
;

sets
service_type                             ancillary service type                                                  /f_response, reserve/
hh_minup(h) max minup hours / 0*23 /
hh_mindown(h) /0*7/;
;

$endIf

$IF "%store_uc%" == ON $INCLUDE highres_storage_uc_setup.gms

$IF "%UC%" == ON $INCLUDE highres_uc_setup.gms

$IF "%water%" == ON $INCLUDE highres_water_setup.gms

$IF "%hydrores%" == ON $INCLUDE highres_hydro.gms



$ifThen NOT "%fx_caps_to%" == ""

parameters
par_new_pcap_z(z,g)
par_exist_pcap_z(z,g)
par_new_store_pcap_z(z,s)
par_exist_store_pcap_z(z,s)
par_new_store_ecap_z(z,s)
par_exist_store_ecap_z(z,s)
par_trans_pcap(z,z_alias,trans)
;

$INCLUDE %fx_caps_to%.dd
;

var_new_pcap_z.FX(z,g) = par_new_pcap_z(z,g);
var_exist_pcap_z.FX(z,g)=par_exist_pcap_z(z,g);

* redefine area, vre_lim and gen_lim so all VREs can be fixed

parameter area(vre,z,r);
area(vre,z,r)$(ord(z) eq ord(r))=par_new_pcap_z(z,vre);

vre_lim(vre,z,r)=((area(vre,z,r)+exist_vre_cap_r(vre,z,r))>0.);
gen_lim(z,vre)=sum(r,(area(vre,z,r)>0.));

var_new_store_pcap_z.FX(z,s)=par_new_store_pcap_z(z,s);
var_exist_store_pcap_z.FX(z,s)=par_exist_store_pcap_z(z,s);
var_new_store_ecap_z.FX(z,s)=par_new_store_ecap_z(z,s);
var_exist_store_ecap_z.FX(z,s)=par_exist_store_ecap_z(z,s);

var_trans_pcap.FX(z,z_alias,trans)=par_trans_pcap(z,z_alias,trans);


$endIf


Equations
eq_obj

eq_costs_gen_capex
eq_costs_gen_fom
eq_costs_gen_varom
$IF "%UC%" == ON eq_costs_gen_start
eq_costs_store_capex
eq_costs_store_fom
eq_costs_store_varom
$IF "%store_uc%" == ON eq_costs_store_start
eq_costs_trans_capex
eq_costs_trans_fom

eq_elc_balance

eq_new_pcap
eq_exist_pcap
eq_tot_pcap
eq_tot_pcap_z

eq_gen_max
eq_gen_min
eq_ramp_up
eq_ramp_down
*eq_curtail_max_non_vre

eq_new_vre_pcap_z
eq_exist_vre_pcap_z
eq_gen_vre
eq_gen_vre_r

eq_area_max

eq_trans_flow
eq_trans_bidirect


eq_co2_budget

*eq_cap_margin

;

******************************************
* OBJECTIVE FUNCTION
******************************************

eq_obj .. costs =E= sum(z,

costs_gen_capex(z)
+costs_gen_fom(z)
+costs_gen_varom(z)
$IF "%UC%" == ON +costs_gen_start(z)
+costs_store_capex(z)
+costs_store_fom(z)
+costs_store_varom(z)
$IF "%store_uc%" == ON +costs_store_start(z)
+costs_trans_capex(z)
+costs_trans_fom(z));


eq_costs_gen_capex(z) .. costs_gen_capex(z) =E= sum(g,var_new_pcap_z(z,g)*gen_capex(g));

eq_costs_gen_fom(z) .. costs_gen_fom(z) =E= sum(g,var_new_pcap_z(z,g)*gen_fom(g))+sum(g,var_exist_pcap_z(z,g)*gen_fom(g));

eq_costs_gen_varom(z) .. costs_gen_varom(z) =E= sum((h,gen_lim(z,g)),var_gen(h,z,g)*gen_varom(g));

$ifThen "%UC%" == ON

eq_costs_gen_start(z) .. costs_gen_start(z) =E= sum((h,non_vre)$(gen_uc_int(non_vre) and gen_lim(z,non_vre)),var_up_units(h,z,non_vre)*gen_startupcost(non_vre))
+sum((h,non_vre)$(gen_uc_lin(non_vre) and gen_lim(z,non_vre)),var_up_units_lin(h,z,non_vre)*gen_startupcost(non_vre));

$endIf

eq_costs_store_capex(z) .. costs_store_capex(z) =E= sum(s,var_new_store_pcap_z(z,s)*store_pcapex(s)+var_new_store_ecap_z(z,s)*store_ecapex(s));

eq_costs_store_fom(z) .. costs_store_fom(z) =E= sum(s,var_exist_store_pcap_z(z,s)*store_fom(s))+sum(s,var_new_store_pcap_z(z,s)*store_fom(s));

eq_costs_store_varom(z) .. costs_store_varom(z) =E= sum((h,s)$s_lim(z,s),var_store_gen(h,z,s)*store_varom(s));

$IF "%store_uc%" == ON eq_costs_store_start(z) .. costs_store_start(z) =E= sum((h,s_lim(z,store_uc_lin)),var_store_up_units_lin(h,z,store_uc_lin)*store_startupcost(store_uc_lin));

eq_costs_trans_capex(z) .. costs_trans_capex(z) =E=

sum(trans_links(z,z_alias,trans),var_trans_pcap(z,z_alias,trans)*trans_links_dist(z,z_alias,trans)*trans_line_capex(trans))
+sum(trans_links(z,z_alias,trans),var_trans_pcap(z,z_alias,trans)$(trans_links_dist(z,z_alias,trans))*trans_sub_capex(trans)*2);

* assume 2% fom costs for transmission

eq_costs_trans_fom(z) .. costs_trans_fom(z) =E= costs_trans_capex(z)*0.02;



******************************************
* SUPPLY-DEMAND BALANCE EQUATION (hourly)
******************************************

eq_elc_balance(h,z) ..

* Generation
sum(gen_lim(z,g),var_gen(h,z,g))

* NonVRE Curtailment due to ramp rates
*-sum(non_vre,var_non_vre_curtail(z,h,non_vre))

* Transmission, import-export
-sum(trans_links(z,z_alias,trans),var_trans_flow(h,z_alias,z,trans))
+sum(trans_links(z,z_alias,trans),var_trans_flow(h,z,z_alias,trans)*(1-(trans_links_dist_bidir(z,z_alias,trans)*trans_loss(trans))))

$ifThen "%storage%" == ON

* Storage, generated-stored
-sum(s_lim(z,s),var_store(h,z,s))
+sum(s_lim(z,s),var_store_gen(h,z,s))

$endIf

$IF "%pen_gen%" == ON +var_pgen(h,z)

=E= demand(z,h);

* +sum(gen_lim(z,g)$(dem(g)),var_gen(h,z,g));


******************************************

*** Capacity balance ***

eq_new_pcap (g) .. sum(gen_lim(z,g),var_new_pcap_z(z,g)) =E= var_new_pcap(g);

eq_exist_pcap(g) .. sum(gen_lim(z,g),var_exist_pcap_z(z,g)) =E= var_exist_pcap(g);

eq_tot_pcap_z(z,g) .. var_new_pcap_z(z,g) + var_exist_pcap_z(z,g) =E= var_tot_pcap_z(z,g);

eq_tot_pcap(g) .. sum(z,var_tot_pcap_z(z,g)) =E= var_tot_pcap(g);

*********************
*** VRE equations ***
*********************

* VRE generation is input data x capacity in each region

eq_gen_vre_r(h,vre_lim(vre,z,r)) .. var_vre_gen_r(h,z,vre,r) =L= vre_gen(h,vre,r)*(var_new_vre_pcap_r(z,vre,r)+var_exist_vre_pcap_r(z,vre,r));

* VRE gen at regional level aggregated to zonal level

eq_gen_vre(h,z,vre) .. var_gen(h,z,vre) =E= sum(vre_lim(vre,z,r),var_vre_gen_r(h,z,vre,r));

* VRE capacity across all regions in a zone must be equal to capacity in that zone

eq_new_vre_pcap_z(z,vre) .. sum(vre_lim(vre,z,r),var_new_vre_pcap_r(z,vre,r)) =E= var_new_pcap_z(z,vre);

eq_exist_vre_pcap_z(z,vre) .. sum(vre_lim(vre,z,r),var_exist_vre_pcap_r(z,vre,r)) =E= var_exist_pcap_z(z,vre);

* VRE capacity in each region must be less than or equal to buildable MW as governed by buildable area for each technology in that region

eq_area_max(vre_lim(vre,z,r)) .. var_new_vre_pcap_r(z,vre,r) =L= area(vre,z,r);


*************************
*** NON VRE equations ***
*************************

* Maximum generation of Non VRE

eq_gen_max(gen_lim(z,non_vre),h)$(gen_lin(z,non_vre)) .. var_tot_pcap_z(z,non_vre)*gen_af(non_vre) =G= var_gen(h,z,non_vre) ;

* Minimum generation of Non VRE

eq_gen_min(mingen_on(z,non_vre),h)$(gen_lin(z,non_vre)) .. var_gen(h,z,non_vre) =G= var_tot_pcap_z(z,non_vre)*gen_mingen_lin(non_vre);

* Ramp equations applied to Non VRE generation, characterised as fraction of total installed
* capacity per hour

eq_ramp_up(h,ramp_on(z,non_vre))$(gen_lin(z,non_vre)) .. var_gen(h,z,non_vre) =L= var_gen(h-1,z,non_vre)+(gen_maxramp(non_vre)*60./gen_unitsize(non_vre))*var_tot_pcap_z(z,non_vre) ;

eq_ramp_down(h,ramp_on(z,non_vre))$(gen_lin(z,non_vre)) .. var_gen(h,z,non_vre) =G= var_gen(h-1,z,non_vre)-(gen_maxramp(non_vre)*60./gen_unitsize(non_vre))*var_tot_pcap_z(z,non_vre) ;

* Non VRE curtailment due to ramping/min generation

*eq_curtail_max_non_vre(ramp_and_mingen(z,non_vre),h) .. var_non_vre_curtail(z,h,non_vre) =L= var_non_vre_gen(z,h,non_vre);


******************************
*** Transmission equations ***
******************************

* Transmitted electricity each hour must not exceed transmission capacity

eq_trans_flow(h,trans_links(z,z_alias,trans)) .. var_trans_flow(h,z,z_alias,trans) =L= var_trans_pcap(z,z_alias,trans);

* Bidirectionality equation is needed when investments into new links are made...I think :)

eq_trans_bidirect(trans_links(z,z_alias,trans)) ..  var_trans_pcap(z,z_alias,trans) =E= var_trans_pcap(z_alias,z,trans);


***********************
*** Misc. equations ***
***********************

* Emissions limit - European average


eq_co2_budget(yr) .. sum((gen_lim(z,non_vre),h)$(hr2yr_map(yr,h)),var_gen(h,z,non_vre)*gen_emisfac(non_vre))*1E3 =L=

sum((z,h)$(hr2yr_map(yr,h)),demand(z,h))*2.


equations
eq_co2_uk_target
;

* UK specific emissions limit

eq_co2_uk_target(yr) .. sum((gen_lim(z,non_vre),h)$(hr2yr_map(yr,h) and uk_z(z)),var_gen(h,z,non_vre)*gen_emisfac(non_vre))*1E3 =L=

sum((z,h)$(hr2yr_map(yr,h) and uk_z(z)),demand(z,h))*2.



scalar dem_tot;
dem_tot=sum((z,h),demand(z,h));

* Capacity Margin

*scalar dem_max;
*dem_max=smax(h,sum(z,demand(z,h)));

*eq_cap_margin .. sum(non_vre,var_tot_pcap(non_vre)*gen_peakaf(non_vre))+sum(vre,var_tot_pcap(vre)*gen_peakaf(vre)) =G= dem_max*1.1 ;

*eq_max_cap(z,g) .. var_cap_z(z,g)+sum(vre_lim(vre,z,r),exist_vre_cap_r(z,vre,r))+gen_exist_pcap_z(z,non_vre) =L= max_cap(z,g)

* Equation for minimum renewable share of generation, set based on restricting non VRE generation.

set flexgen(non_vre) / NaturalgasOCGTnew / ;

$IF "%RPS%" == "optimal" $GOTO optimal
Equations eq_max_non_vre;
eq_max_non_vre .. sum((h,z,non_vre)$(gen_lim(z,non_vre) and not flexgen(non_vre)),var_gen(h,z,non_vre)) =E= dem_tot*(1-RPS_scalar);
$label optimal

* BECCS constraint

$ifThenE (sameas('%psys_scen%','BECCS'))or(sameas('%psys_scen%','ALL'))

equations
eq_uk_max_beccs
;

set beccs(non_vre) / BiomassCCS /;

eq_uk_max_beccs .. sum((gen_lim(z,non_vre),h)$(beccs(non_vre) and uk_z(z)),var_gen(h,z,non_vre)) =L= 61E3*0.281;

$endIf

* Transmission constraints


* If yes this will force net zero flows of power between UK and Europe over the year

$ifThen "%nz_trans%" == YES

equations
eq_uk_nz_import
;

eq_uk_nz_import(z,z_alias,trans)$(uk_z(z) and not_uk_z_alias(z_alias) and trans_links(z,z_alias,trans)) ..

sum(h,var_trans_flow(h,z,z_alias,trans))*(1-(trans_links_dist_bidir(z,z_alias,trans)*trans_loss(trans)))

-sum(h,var_trans_flow(h,z_alias,z,trans)) =E= 0. ;


$endIf

scalar max_import;

$ifThen "%fx_trans%" == YES
max_import=0.3
$else
max_import=0.5
$endIf


parameter uk_dem(h);
uk_dem(h)=sum(uk_z(z),demand(z,h));

equation
eq_uk_import_max
;

* Limit max hourly imports by UK to be share of UK domestic demand - either 30% or 50%

eq_uk_import_max(h) ..


sum((trans_links(z,z_alias,trans))$(uk_z(z) and not_uk_z_alias(z_alias)),var_trans_flow(h,z,z_alias,trans)*(1-(trans_links_dist_bidir(z,z_alias,trans)*trans_loss(trans))))

-sum(trans_links(z,z_alias,trans)$(uk_z(z) and not_uk_z_alias(z_alias)),var_trans_flow(h,z_alias,z,trans))

=L= sum(uk_z(z),demand(z,h))*max_import;


set not_uk(z);
not_uk(z)$(not uk_z(z)) = YES;


equations
eq_eu_max_import
;

* Max hourly import limits applied to European countries

eq_eu_max_import(z,h)$(not_uk(z)) ..

sum(trans_links(z,z_alias,trans),var_trans_flow(h,z,z_alias,trans)*(1-(trans_links_dist_bidir(z,z_alias,trans)*trans_loss(trans))))

-sum(trans_links(z,z_alias,trans),var_trans_flow(h,z_alias,z,trans))

=L= demand(z,h)$(not_uk(z))*max_import;






Model Dispatch /all/;

* don't usually use crossover but can be used to ensure
* a simplex optimal solution is found

Option LP = CPLEX;
Option MIP = CPLEX;

$ifThen %cplex_opt_file% == 1

$set cplex_fname "cplex.opt"

$else

$set cplex_fname "cplex.op%cplex_opt_file%"

$endIf

$onecho > %cplex_fname%


cutpass=-1

solvefinal=0
epgap=0.01

barorder=0
baralg=0
solutiontype=2
barepcomp=1E-7
subalg=4
numericalemphasis=0

heurfreq=1

lpmethod=4
threads=5
startalg=4

parallelmode=-1
tilim=720000
mipdisplay=5
names yes
scaind=1
epmrk=0.9999
clonelog=1
mipkappastats=1
perind=1



$offecho
Dispatch.OptFile = 1;

*numericalemphasis=1
*dpriind=5

$ontext

writelp="C:\science\highRES\development\highres.lp"

epopt=1E-4
eprhs=1E-4
var_n_units.prior(z,non_vre) = 1;
var_up_units.prior(z,h,non_vre)=100;
var_down_units.prior(z,h,non_vre)=100;
var_com_units.prior(z,h,non_vre)=100;
Dispatch.prioropt=1;
$offtext


* 12:18
* 11 min bar order=3 and baralg=1

*writelp="C:\science\highRES\work\highres.lp"

* 2003 flexgen+store baralg=2, scaind=1 optimal
* barepcomp=1E-8
* ppriind=1

*execute_loadpoint "hR_dev";

$ifThen "%UC%" == ON

Solve Dispatch minimizing costs using MIP;

$else

Solve Dispatch minimizing costs using MIP;

$endIf


parameter trans_f(h,z,z_alias,trans);
trans_f(h,z,z_alias,trans)=var_trans_flow.l(h,z_alias,z,trans)$(var_trans_flow.l(h,z,z_alias,trans)>1.0);
*display trans_f;

parameter max_bidir_trans;
max_bidir_trans=smax((h,z,z_alias,trans),trans_f(h,z,z_alias,trans));
*display maxtrans;

*parameter pgen_tot;
*pgen_tot=sum((z,h),var_non_vre_gen.l(z,h,"pgen"));

$IF "%log%" == "" $GOTO nolog
scalar now,year,month,day,hour,minute;
now=jnow;
year=gyear(now);
month=gmonth(now);
day=gday(now);
hour=ghour(now);
minute=gminute(now);

scalars  cplex_absgap    absolute gap
         cplex_relgap    relative gap;

cplex_absgap = abs(Dispatch.objest - Dispatch.objval);
cplex_relgap=100*cplex_absgap/abs(Dispatch.objval);

file fname /"%log%"/;
fname.ap=1;
putclose fname "%outname%"","
day:0:0"/"month:0:0"/"year:0:0" "hour:0:0":"minute:0:0","
Dispatch.modelStat:1:0","
Dispatch.resUsd:0
$IF "%UC%" == ON ","cplex_relgap:0
;
$LABEL nolog

* write result parameters

$INCLUDE highres_results.gms

* dump data to GDX

execute_unload "%outname%"

* convert GDX to SQLite

$IF "%gdx2sql%" == ON execute "gdx2sqlite -i %outname%.gdx -o %outname%.db -fast"






