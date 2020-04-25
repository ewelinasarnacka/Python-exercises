

/*Ewelina Cichocka*/
/*2011-12-07*/
%check_for_database(n=1,baza1=in03prd.policy, baza2=in03prd.policy, baza3=in03prd.policy, baza4= in03prd.policy, baza5=in03prd.policy, nazwa_raportu=BINSIS-180);
options ls=150 pagesize=30;
%let today = %sysfunc(date(),yymmdd10.);

%macro change_datetime_format(table,variable);
data &table;
set &table;
	&variable=datepart(&variable);
	format &variable yymmdd10.;
run;
%mend;

/***********************************************************************************************************************************************************************/
/* Wszystkie polisy w statusie >=0 z dat¹ pocz¹tku startu */
/***********************************************************************************************************************************************************************/

proc sql;
create table policy as 
select insr_type, policy.policy_id, 0 as annex_id, policy.policy_state, hps.name as policy_state_desc, 
       policy.insr_begin, policy.insr_end, policy.convert_date
  from in03prd.policy policy
	   left join in03prd.hst_policy_state hps on policy.policy_state=hps.id
 where policy.policy_state in (0,11,12,30)
   and insr_type in (1001,1101,1201)
;quit;
%change_datetime_format(policy,insr_begin);
%change_datetime_format(policy,insr_end);
%change_datetime_format(policy,state_change);
%change_datetime_format(policy,convert_date);

data policy;
set policy;
	 format date_start yymmdd10. date_end yymmdd10.;
	 date_start = intnx('year',today(),-1,'begin');
	 date_end = intnx('month',today(),-1,'end');
run;

proc sql print ;
select distinct date_start into:date_start
from policy;
quit;
%PUT &date_start;
proc sql print ;
select distinct date_end into:date_end
from policy;
quit;
%PUT &date_end;
proc sql print ;
select distinct year(date_end) as rok into:rok
from policy;
quit;
%PUT &rok;
proc sql print ;
select distinct month(date_end) as miesiac into:miesiac
from policy;
quit;
%PUT &miesiac;
proc sql print ;
select distinct day(date_end) as dzien into:dzien
from policy;
quit;
%PUT &dzien;

data czasy_trwania;
set arc01prd.czasy_trwania;
run;
%biblioteki;
proc sql;
create table oc_bez_ochrony as
select distinct policy_id, min(insr_begin) as insr_begin format datetime19., max(insr_end) as insr_end format datetime19.
from in03prd.gen_risk_covered
/*where cover_type in ('MTPL','ASS_MINI','GREENCARD')*/
group by policy_id
;
quit;
proc sql;
create table oc_bez_ochrony as 
select * from oc_bez_ochrony 
where insr_begin=insr_end;
quit;
proc sql; /*9 205 369*/
create table czasy_trwania as
select * from czasy_trwania 
where policy_id not in (select policy_id from oc_bez_ochrony);
quit;

%biblioteki;
proc sql;
create table premiums_gl as
select policy_id, round(sum(premium), 0.01) as premium_gl
from (select policy_id, cover_type, fract_type, account_date, case when ct_account like 'DP%' then amount else 0 end as premium
          from in03prd.gl_insis2gl
         where ct_account like 'DP%'
             and datepart(account_date) <= mdy(&miesiac.,&dzien.,&rok.)) 
group by policy_id
;
quit;
proc sql;
create table policy_gl as
select p.policy_id, 0 as annex_id, 'MTPL' as cover_type,  p.insr_type,  insr_begin as poczatek, insr_end as  koniec /*, premium_gl as premium, 
		intnx('year',insr_begin,+1) as aniversary format yymmdd10., premium_gl as skladka_roczna*/
from policy p
left join premiums_gl g on g.policy_id=p.policy_id
where p.policy_id not in (select policy_id from czasy_trwania)
and insr_begin<=mdy(&miesiac.,&dzien.,&rok.) and insr_end >= mdy(&miesiac,&dzien,&rok)
and premium_gl>0
and insr_type in (1001, 1201, 1101)
;
quit;

proc sql;
create table czasy_trwania2 as
select distinct * from czasy_trwania
union 
select distinct * from policy_gl;
run;
/**/
/*proc sql;*/
/*create table z_test as*/
/*select distinct count(distinct policy_id) as l_polis, year(poczatek) as rok, month(poczatek) as miesiac from policy_gl */
/*group by year(poczatek),  month(poczatek)*/
/*;*/
/*quit;*/



proc sql;
create table czasy_trwania as
select policy_id, cover_type, min(poczatek) as poczatek format yymmdd10., max(koniec) as koniec format yymmdd10.
  from czasy_trwania
 group by policy_id, cover_type
 order by policy_id, cover_type
;quit;
data czasy_trwania;
set czasy_trwania;
if poczatek <= mdy(&miesiac,&dzien,&rok) and koniec >= mdy(&miesiac,&dzien,&rok) then in_force = 1; else in_force=0;
run;

/*data skladka_mr;*/
/*set nadysk.skladka_mr;*/
/*run;*/

/***********************************************************************************************************************************************************************/
/* POLISY SPRZEDANE I NIE ANULOWANE */
/***********************************************************************************************************************************************************************/

proc sql;
create table CEPiK_sale as
select t.policy_id, datepart(insr_begin) as insr_begin format yymmdd10. ,  datepart(insr_end) as insr_end format yymmdd10. , policy_state, convert_date
  from (select policy_id, min(poczatek) as insr_begin format yymmdd10., max(koniec) as insr_end format yymmdd10.
		  from czasy_trwania
		 group by policy_id ) t 
       left join (select policy_id, policy_state, convert_date from policy) p on p.policy_id=t.policy_id
/*	   left join (select policy_id, cala_skladka as skladka from skladka_mr) smr on smr.policy_id=t.policy_id*/
 order by policy_id
;quit;
data CEPiK_sale;
set CEPiK_sale;	 
year_begin=year(insr_begin);
month_begin=month(insr_begin);
where year(today( )) > year(insr_begin) or (year(today( )) = year(insr_begin) and month(today( )) > month(insr_begin)); /* !!!!! */
run;
/*data nadysk.cepik_sale_06_08_2014;*/
/*set cepik_sale;*/
/*run;*/
proc sql;
create table CEPiK_sale_report as 
select year_begin, month_begin, count(unique policy_id) as policy_sale_all, 
       case when year_begin = 2011 then 3.9622  
            when year_begin = 2012 then 4.4640 
            when year_begin = 2013 then 4.0671 
			when year_begin = 2014 then 4.1631 
			when year_begin = 2015 then 4.3078
						else 0 end as exchange_rate
  from CEPiK_sale
 group by year_begin, month_begin
;quit;

/***********************************************************************************************************************************************************************/
/* POLISY SPRZEDANE I ANULOWANE */
/***********************************************************************************************************************************************************************/

proc sql;
create table CEPiK_cancel as 
select policy.policy_id, 0 as annex_id, hps.name as policy_state, 
       policy.insr_begin, policy.insr_end, policy.convert_date
  from in03prd.policy policy
	   left join in03prd.hst_policy_state hps on policy.policy_state=hps.id
	   left join (select * from czasy_trwania where cover_type = 'MTPL') ct on ct.policy_id=policy.policy_id
 where policy.policy_state in (30)
   and policy.policy_id not in (select policy_id from czasy_trwania)
   and policy.insr_type in (1001,1101,1201)
/*   and datepart(insr_begin)<=mdy(&miesiac,&dzien,&rok)*/
;quit;


%change_datetime_format(CEPiK_cancel,insr_begin);
%change_datetime_format(CEPiK_cancel,insr_end);
%change_datetime_format(CEPiK_cancel,convert_date);
data CEPiK_cancel;
set CEPiK_cancel;	 
year_begin=year(insr_begin);
month_begin=month(insr_begin);
where year(today( )) > year(insr_begin) or ( year(today( )) = year(insr_begin) and month(today( )) > month(insr_begin)); /* !!!!! */
run;

proc sql;
create table CEPiK_cancel_report as 
select year_begin, month_begin, count(unique policy_id) as policy_cancel_all
  from CEPiK_cancel
 group by year_begin, month_begin
;quit;

/***********************************************************************************************************************************************************************/
/* POLISY DO ZARAPORTOWANIA DO CEPiK */
/***********************************************************************************************************************************************************************/

proc sql;
create table CEPiK_report as 
 select year_begin, month_begin, 
        policy_sale_all + policy_cancel_all as policy_to_report,
        policy_cancel_all as cancelation_to_report, policy_sale_all as policy_net, 
		(policy_sale_all)*(1.00) as policy_value_euro,
		(policy_sale_all)*(exchange_rate) as policy_value_pln, exchange_rate
  from (
		select cs.year_begin, cs.month_begin, policy_sale_all, 
               case when policy_cancel_all=. then 0 else policy_cancel_all end as policy_cancel_all, 
               exchange_rate
		  from CEPiK_sale_report cs
               left join CEPiK_cancel_report cc on cc.year_begin=cs.year_begin and cc.month_begin=cs.month_begin
		) 
;quit;

/***********************************************************************************************************************************************************************/
/* IMPORT CSV Z POPRZEDNIEGO MIESI¥CA */
/***********************************************************************************************************************************************************************/

data IMPORT;
format report_previous_date yymmdd10.;
report_previous_date = intnx('MONTH',today(),-1,'begin');
run;
proc sql print;
select unique report_previous_date into:report_previous
from IMPORT;
quit;
%put &report_previous;

proc import datafile= "P:\DEP\actuarial\06 REPORTS - FINANCIAL\01 Sprawozdania z oplat ewidencyjnych\BINSIS - 180 - CEPiK\RAPORTY\C3_BINSIS - 180 - CEPiK - &report_previous..csv"            
     out= work.report_previous dbms=dlm replace;
     delimiter=",";            
     getnames=yes;
run;

proc sql;
create table CEPiK_report as 
 select year_begin, month_begin, 
        policy_to_report, cancelation_to_report, policy_net, 
        case when policy_net_previous=. then 0 else policy_net_previous end as policy_net_previous,
        case when policy_net_previous=. then (policy_net - 0) else (policy_net - policy_net_previous) end as policy_to_cepik,
		case when policy_net_previous=. then round((policy_net - 0)*(1.00),0.01) else round((policy_net - policy_net_previous)*(1.00),0.01) end as policy_value_euro,
		case when policy_net_previous=. then round((policy_net - 0)*(exchange_rate),0.01) else round((policy_net - policy_net_previous)*(exchange_rate),0.01) end as policy_value_pln, 
        exchange_rate
  from (
		select cr.*, rp.policy_net as policy_net_previous
		  from CEPiK_report cr
               left join report_previous rp on rp.year_begin=cr.year_begin and rp.month_begin=cr.month_begin
		) 
 where (year(today())= year_begin)  or (year(today())-1= year_begin and month(today()) <= month_begin)
;quit;

/***********************************************************************************************************************************************************************/
/*EKSPORT DO MS EXCEL*/
/***********************************************************************************************************************************************************************/

data EXPORT;
format report_date yymmdd10.;
report_date = intnx('MONTH',today(),+0,'begin');
run;
proc sql print;
select unique report_date into:report_date
from EXPORT;
quit;
%put &report_date;
%put &today;

ods xml body="P:\DEP\actuarial\06 REPORTS - FINANCIAL\01 Sprawozdania z oplat ewidencyjnych\BINSIS - 180 - CEPiK\RAPORTY\C3_BINSIS - 180 - CEPiK - &report_date..csv" type=csv;
proc print data=CEPiK_report;
run;
ods xml close;

ODS tagsets.excelxp file="P:\DEP\actuarial\06 REPORTS - FINANCIAL\01 Sprawozdania z oplat ewidencyjnych\BINSIS - 180 - CEPiK\RAPORTY\C3_BINSIS - 180 - CEPiK - &today..xls"
                   style=MeadowPrinter 
                   options(embedded_titles='yes' embedded_footnotes='yes' sheet_name='CEPiK Report' frozen_headers='5'
                           sheet_interval='bygroup' autofilter='all' /*autofilter_width="7em" autofilter_table="1"*/);
PROC REPORT DATA=CEPiK_report nowd headline headskip split='*'; 
column year_begin month_begin 
       policy_to_report cancelation_to_report policy_net policy_net_previous 
       policy_to_cepik policy_value_euro policy_value_pln exchange_rate;
define year_begin  /display 'Year Begin'  style(column)={cellwidth=1.0in};
define month_begin /display 'Month Begin' style(column)={cellwidth=1.0in};
define policy_to_report      /analysis sum'Number of Policy*to report'              style(column)={cellwidth=1.5in};
define cancelation_to_report /analysis sum 'Number of Policy Cancelation*to report (total cancel)' style(column)={cellwidth=2.0in};
define policy_net            /analysis sum 'Number of Policy Net*(current report)'  style(column)={cellwidth=1.5in};
define policy_net_previous   /analysis sum 'Number of Policy Net*(previous report)' style(column)={cellwidth=1.5in};
define policy_to_cepik   /analysis sum 'Number of Policy*to Report to CEPiK'        style(column)={cellwidth=1.5in};
define policy_value_euro /analysis sum 'Due Premium*(in EURO)' format=nlmnleur32.2  style(column)={cellwidth=1.0in};
define policy_value_pln  /analysis sum 'Due Premium*(in PLN)'  format=nlmnlpln32.2  style(column)={cellwidth=1.0in}; 
define exchange_rate /display 'Exchange Rate' format=nlmnlpln32.4 style(column)={cellwidth=1.0in};   
rbreak after/summarize dol dul style=[font_weight=bold color=green fontstyle=roman font_size=2 background=#EBF2E6] ;
title1 j=c bold color=black height=12pt font=Arial bcolor=white '   ' /*=left '^S={preimage="P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\08 Underwriting\LOGO.png"}'*/;
title2 j=c bold color=green height=13pt font=Arial bcolor=white 'CEPiK REPORT - 1 EURO';
title3 j=c bold color=black height=12pt font=Arial bcolor=white "Report Date: %sysfunc(date(),worddate18.)";
RUN;
ODS tagsets.excelxp close;
ods listing;
/***********************************************************************************************************************************************************************/
/*WYS£ANIE NA EMAIL*/
/***********************************************************************************************************************************************************************/
/*%dodaj_odbiorce(180,1,'Agnieszka1.Pawlak@proama.pl');*/
/*%dodaj_odbiorce(180,1,'agata.kariozen@proama.pl');*/
/*%dodaj_odbiorce(180,1,'Aldona.Szacherska@proama.pl');*/
/*%dodaj_odbiorce(180,1,'luiza.smargol@proama.pl');*/
/*%dodaj_odbiorce(180,1,'monika.wisniewska@proama.pl');*/
/*%dodaj_odbiorce(180,2,'krzysztof.wanatowicz@proama.pl');*/
/*%dodaj_odbiorce(180,2,'olivier.faucher@proama.pl');*/
/*%dodaj_odbiorce(180,2,'ewelina.cichocka@proama.pl');*/
%odbiorcy(180);

x 'cd P:\DEP\Actuarial\05 REPORTS - OPERATIONAL\16 SAS - Macro';
%inc "MIS - email - tekst - MIS.sas";

%let row_num=0;
proc sql noprint;
select count(*) as row_num into: row_num
from CEPiK_report;
quit;
%put &row_num;

%macro wyslij_error();
%if (&row_num. <= 5 ) %then %do;
%runtime(BINSIS-180,1);
options emailsys=smtp emailhost=email4app.groupama.local emailport=587; 
filename mymail email (&odbiorca1.)
    type = 'text/html' 
 subject = "ERROR - BINSIS-180 - CEPIK - MIS - Finance - &today." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 replyto = "ZespolAnalizIRaportowania@proama.pl"
      cc = ("ZespolAnalizIRaportowania@proama.pl" &odbiorca2.) ;
%let stopka1 = " ";
%let stopka2 = "Raport CEPIK - MIS - Finance - &today. - wyst¹pi³ b³¹d podczas generowania raportu.";
%let stopka3 = " ";
%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);
%end;
%mend; 

%wyslij_error();


%macro wyslij();
%if (&row_num. > 5 ) %then %do;
%runtime(BINSIS-180,0);
options emailsys=smtp emailhost=ex1prod.groupama.local emailport=587 sortseq=Polish; 
filename mymail email (&odbiorca1.)
content_type="text/html" 
subject="BINSIS-180 - CEPiK - 1 EURO Report &today." 
    from = "Zespol Analiz i Raportowania <ZespolAnalizIRaportowania@proama.pl>"
 	replyto = "ZespolAnalizIRaportowania@proama.pl"
    cc = ("ZespolAnalizIRaportowania@proama.pl" &odbiorca2.)
	attach="P:\DEP\actuarial\06 REPORTS - FINANCIAL\01 Sprawozdania z oplat ewidencyjnych\BINSIS - 180 - CEPiK\RAPORTY\C3_BINSIS - 180 - CEPiK - &today..xls";
%let stopka1='Agata, Agnieszka,';
%let stopka2="please find attached the report for CEPiK, as of &today..";
%let stopka3=' ';
%email_tekst_MIS (&stopka1., &stopka2., &stopka3.);
%end;
%mend; 

%wyslij();
