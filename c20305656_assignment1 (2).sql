USE MusicCompDB;

DROP TABLE IF EXISTS FactVote;
DROP table if EXISTS DimParticipant;
DROP TABLE IF EXISTS DimViewer;
Drop TABLE IF EXISTS DimTime;

/*
    creating star dimensional model
*/

CREATE TABLE DimTime (
    Edition_Year year(4),
    voteDate date,
    TimeSK INT PRIMARY KEY
);

CREATE TABLE DimViewer(
    viewerSK INT primary key,
    age_group_desc VARCHAR(50),
    v_countyName VARCHAR(50),
    voteCategory varchar(15)
);

CREATE TABLE DimParticipant(
    p_name varchar(255),
    p_countyName varchar(50),
    participant_SK INT PRIMARY KEY
);

create table FactVote(
    vote int(11),
    cost float,
    voteMode varchar(10),
    participant_SK INT,
    viewerSK INT,
    TimeSK INT,
    CONSTRAINT  PK_fact PRIMARY KEY (participant_SK,viewerSK,TimeSK),
    CONSTRAINT  p_sk FOREIGN KEY (participant_SK) REFERENCES DimParticipant,
    CONSTRAINT  v_sk FOREIGN KEY (viewerSK) REFERENCES DimViewer,
    CONSTRAINT  t_sk FOREIGN KEY (TimeSK) REFERENCES DimTime
);

/*
    participant stage and load
*/

DROP TABLE IF EXISTS stage_participant;

/* creating an empty staging table using the PARTICIPANTS table */
create table stage_participant select PARTNAME from PARTICIPANTS where 1=0;

alter table stage_participant add p_countyName  varchar(50);

/* populating table with requierd values */
INSERT INTO stage_participant 
select PARTNAME, COUNTYNAME 
from PARTICIPANTS
JOIN COUNTY ON PARTICIPANTS.COUNTYID = COUNTY.COUNTYID;

select * from stage_participant;

/* creating the surrogate key */
alter table stage_participant add participant_SK INT;
select * from stage_participant;

/* creating a sequence, value will be used for the surrogate key */
drop sequence if exists p_seq;
CREATE sequence p_seq
start with 1
increment by 1;

/* populating the surrogate key */
update stage_participant 
SET participant_SK = (NEXT VALUE for p_seq);

SELECT * FROM stage_participant;

/* load into star model dimension */
INSERT INTO DimParticipant select * from stage_participant;

SELECT * FROM DimParticipant;

/*
    Time staging and loading
*/

/* creating staging table */
DROP TABLE IF EXISTS stage_Time;
create table stage_Time(
    t_EDYear year(4),
    t_voteDate date
);

/* populating the time staging table */
insert into stage_Time
select distinct EDYEAR, VOTEDATE 
FROM Edition
join VOTES ON Edition.EDYEAR = VOTES.EDITION_YEAR;

select * from stage_Time;

/* adding a column for the surrogate key */
alter table stage_Time add edition_sk INT;

/* creating a sequence */
drop sequence if exists edition_seq;
create sequence edition_seq 
start with 1 
increment by 1 ; 

update stage_Time
SET edition_sk = (NEXT VALUE FOR edition_seq);

select * from stage_Time;

/* load into star model dimension */
insert into DimTime 
select t_EDYear, t_voteDate, edition_sk
from stage_Time;

select * from DimTime;

/*
    Viewer stage and load
*/

/* creating staging table */
DROP TABLE IF EXISTS stage_viewer;

create table stage_viewer(
    viewerID int(11),
    age_group int(11),
    countyID int(11),
    GROUP_DESC varchar(50),
    county_name varchar(50),
    voteCat int(11)
);

/* populating staging table for viewer */
INSERT INTO stage_viewer(viewerID,age_group,countyID, GROUP_DESC, county_name, voteCat)
select distinct VIEWERS.VIEWERID, AGE_GROUP, VIEWERS.COUNTYID, age_group_desc, COUNTYNAME, VOTE_CATEGORY 
from VIEWERS
join AGEGROUP on VIEWERS.AGE_GROUP = AGEGROUP.AGE_GROUPID
join COUNTY ON VIEWERS.COUNTYID = COUNTY.COUNTYID
join VOTES on VIEWERS.VIEWERID = VOTES.VIEWERID;

/* changing the numerical value of vote_category to show what the number represents for easier readability */
alter table stage_viewer add catagory varchar(15);
update stage_viewer set catagory = 'audience' where voteCat=1;
update stage_viewer set catagory = 'experts jury' where voteCat=2;

select * from stage_viewer;

/* creating the surrogate key */
alter TABLE stage_viewer add s_viewerSK int;

/* creating a sequence for the surrogate key */
DROP SEQUENCE IF EXISTS viewer_seq;
create sequence viewer_seq 
start with 1 
increment by 1 ; 

update stage_viewer set s_viewerSK = (NEXT VALUE FOR viewer_seq);

select * from stage_viewer;

/* load into star model dimension */
insert INTO DimViewer(viewerSK, age_group_desc, v_countyName, voteCategory)
select s_viewerSK, GROUP_DESC, county_name, catagory from stage_viewer;

select * from DimViewer;


/* 
    fact table stage and load 
*/

/* creating staging table */
DROP TABLE IF EXISTS stage_fact;
create TABLE stage_fact(
    v_id INT,
    votedate date,
    p_name varchar(50),
    vote int,
    voteMethod varchar(10),
    vote_cat int,
    edYear year(4)
);

/* populating the staging table for the fact */
insert INTO stage_fact
select VIEWERID, VOTEDATE, PARTNAME, VOTE, VOTEMODE, VOTE_CATEGORY, EDITION_YEAR
from VOTES;

select * from stage_fact;

/* add surrogate keys */
alter table stage_fact add p_sk int;
alter table stage_fact add v_sk int;
alter table stage_fact add t_sk int;

/* assigning value to surrogate key using stage_participant as lookup */
update stage_fact
set p_sk = (
    select stage_participant.participant_SK 
    from stage_participant
    where stage_participant.PARTNAME = stage_fact.p_name
);


/* assigning value to surrogate key using stage_Time as lookup */
update stage_fact
set t_sk = (
    select stage_Time.edition_sk 
    from  stage_Time
    where stage_Time.t_voteDate = stage_fact.votedate
);

/* assigning value to surrogate key using stage_viewer as lookup */
update stage_fact
set v_sk = (
    select stage_viewer.s_viewerSK
    from stage_viewer 
    where stage_viewer.viewerID = stage_fact.v_id
    and stage_viewer.voteCat = stage_fact.vote_cat
);

/* creating a new column to store the cost of the vote */
alter table stage_fact add vote_cost float;

/* assigning the appropriate value based on the conditions given in the CA Questions */
update stage_fact
set vote_cost = if(vote_cat = 2, 0.00,
                if(edYear between 2013 and 2015 and (voteMethod = 'Facebook' or voteMethod = 'Instagram'), 0.20,
                if(edYear between 2013 and 2015 and (voteMethod = 'TV' or voteMethod = 'Phone'), 0.50,
                if(edYear between 2016 and 2022 and (voteMethod = 'Facebook' or voteMethod = 'Instagram'), 0.50,
                if(edYear between 2016 and 2022 and (voteMethod = 'TV' or voteMethod = 'Phone'),  1.00, vote_cost)))));

select * from stage_fact;

/* load into fact table */
insert into FactVote 
select vote, vote_cost, voteMethod, p_sk, v_sk, t_sk
from stage_fact;

select * from FactVote;

/*
    Questions:
*/

/*
    1. for each edition of the programme, what is the total votes cast by each age group in each county
        - include the age group dscription and county name in the output
*/

select Edition_Year, count(vote), age_group_desc, v_countyName
from DimTime t
join FactVote F on t.TimeSK = F.TimeSK
join DimViewer v on F.viewerSK = v.viewerSK
group by Edition_Year, age_group_desc, v_countyName;

/* indexing */

/* examining the query using estimated statistics */
explain select Edition_Year, count(vote), age_group_desc, v_countyName
from DimTime t
join FactVote F on t.TimeSK = F.TimeSK
join DimViewer v on F.viewerSK = v.viewerSK
group by Edition_Year, age_group_desc, v_countyName;

/* using ANALYZE to examine the query plan with the actual statistics of the query */
Analyze select Edition_Year, count(vote), age_group_desc, v_countyName
from DimTime t
join FactVote F on t.TimeSK = F.TimeSK
join DimViewer v on F.viewerSK = v.viewerSK
group by Edition_Year, age_group_desc, v_countyName;

/* creating indexes */
create index EDY_index on DimTime(Edition_Year);
create index age_group_index on DimViewer(age_group_desc);
create index countyName_index on DimViewer(v_countyName);


/* re-running the EXPLAIN of the query and forcing the optimizer to use the indexes */
explain select Edition_Year, count(vote), age_group_desc, v_countyName
from DimTime t FORCE INDEX (EDY_index)
join FactVote F on t.TimeSK = F.TimeSK
join DimViewer v FORCE INDEX (age_group_index, countyName_index ) on F.viewerSK = v.viewerSK
group by Edition_Year, age_group_desc, v_countyName;

/* re-running the ANALYZE query to see the effect of the indexes on the actual statistics */
analyze select Edition_Year, count(vote), age_group_desc, v_countyName
from DimTime t FORCE INDEX (EDY_index)
join FactVote F on t.TimeSK = F.TimeSK
join DimViewer v FORCE INDEX (age_group_index, countyName_index ) on F.viewerSK = v.viewerSK
group by Edition_Year, age_group_desc, v_countyName;

/* dropping indexes */
drop index EDY_index on DimTime;
drop index age_group_index on DimViewer;
drop index countyName_index on DimViewer;


/*
    2. For each county, what is the total number of votes recived by each participant in the 2022 edition of
    the program from audience viewers in that county voting for participants from the same count.
        - include the county name in the output
*/

select count(vote), p_name, p_countyName
from DimParticipant p
join FactVote F on p.participant_SK = F.participant_SK
join DimViewer v on F.viewerSK = v.viewerSK
join DimTime t on F.TimeSK = t.TimeSK
where Edition_Year = 2022 and p_countyName = v_countyName
GROUP BY p_name;

/* indexing */

/* examining the query using estimated statistics */
explain select count(vote), p_name, p_countyName
from DimParticipant p
join FactVote F on p.participant_SK = F.participant_SK
join DimViewer v on F.viewerSK = v.viewerSK
join DimTime t on F.TimeSK = t.TimeSK
where Edition_Year = 2022 and p_countyName = v_countyName
GROUP BY p_name;

/* using ANALYZE to examine the query plan with the actual statistics of the query */
Analyze select p.p_name, p.p_countyName, count(F.vote)
from DimParticipant p
join FactVote F on p.participant_SK = F.participant_SK
join DimViewer v on F.viewerSK = v.viewerSK
join DimTime t on F.TimeSK = t.TimeSK
where t.Edition_Year = 2022 and p.p_countyName = v.v_countyName
GROUP BY p.p_name;

/* creating indexes */

/* I created indexes for the where clause to speed up data retrival */
create index EDY_index on DimTime(Edition_Year);
create index p_countyIndex on DimParticipant(p_countyName);
create index v_countyIndex on DimViewer(v_countyName);

/* I created an index for the group by to reduce the scanning of the table */
create index pname_index on DimParticipant(P_NAME);

/* re-running the EXPLAIN of the query and forcing the optimizer to use the indexes */
explain select p.p_name, p.p_countyName, count(F.vote)
from DimParticipant p FORCE INDEX (p_countyIndex, pname_index)
join FactVote F on p.participant_SK = F.participant_SK
join DimViewer v FORCE INDEX (v_countyIndex) on F.viewerSK = v.viewerSK
join DimTime t FORCE INDEX (EDY_index) on F.TimeSK = t.TimeSK
where t.Edition_Year = 2022 and p.p_countyName = v.v_countyName
GROUP BY p.p_name;

/* re-running the ANALYZE query to see the effect of the indexes on the actual statistics */
analyze select p.p_name, p.p_countyName, count(F.vote)
from DimParticipant p FORCE INDEX (p_countyIndex, pname_index)
join FactVote F on p.participant_SK = F.participant_SK
join DimViewer v FORCE INDEX (v_countyIndex) on F.viewerSK = v.viewerSK
join DimTime t FORCE INDEX (EDY_index) on F.TimeSK = t.TimeSK
where t.Edition_Year = 2022 and p.p_countyName = v.v_countyName
GROUP BY p.p_name;

/* dropping indexes */
drop index EDY_index on DimTime;
drop index p_countyIndex on DimParticipant;
drop index v_countyIndex on DimViewer;
drop index pname_index on DimParticipant;


/*
    3. For the 2013 and 2019 edition of the programme respectively, for each county, what was the
    total income earned from audience viewers in that county for each voting category.
        - include the county names and the year in the ouput.
*/

select Edition_Year, v_countyName, round(sum(cost),2), voteCategory
from DimViewer v
join FactVote F on v.viewerSK = F.viewerSK
join DimTime t on F.TimeSK = t.TimeSK
where Edition_Year = 2013 or Edition_Year = 2019
group by v_countyName, Edition_Year, voteCategory;

/* indexing */

/* examining the query using estimated statistics */
explain select Edition_Year, v_countyName, round(sum(cost),2), voteCategory
from DimViewer v
join FactVote F on v.viewerSK = F.viewerSK
join DimTime t on F.TimeSK = t.TimeSK
where Edition_Year = 2013 or Edition_Year = 2019
group by v_countyName, Edition_Year, voteCategory;

/* using ANALYZE to examine the query plan with the actual statistics of the query */
analyze select Edition_Year, v_countyName, round(sum(cost),2), voteCategory
from DimViewer v
join FactVote F on v.viewerSK = F.viewerSK
join DimTime t on F.TimeSK = t.TimeSK
where Edition_Year = 2013 or Edition_Year = 2019
group by v_countyName, Edition_Year, voteCategory;

/* creating indexes */
create index EDY_index on DimTime(Edition_Year);
create index v_countyIndex on DimViewer(v_countyName);
create index catIndex on DimViewer(voteCategory);
/* 
    I created an index on viewerSK because a full table scan is being done on this table
    and there are a lot of rows it would need to scan through
*/
create index viewer_index on DimViewer(viewerSK);

/* re-running the EXPLAIN of the query and forcing the optimizer to use the indexes */
explain select Edition_Year, v_countyName, round(sum(cost),2), voteCategory
from DimViewer v FORCE INDEX (v_countyIndex, catIndex, viewer_index)
join FactVote F on v.viewerSK = F.viewerSK
join DimTime t FORCE INDEX (EDY_index) on F.TimeSK = t.TimeSK
where Edition_Year = 2013 or Edition_Year = 2019
group by v_countyName, Edition_Year, voteCategory;

/* re-running the ANALYZE query to see the effect of the indexes on the actual statistics */
analyze select Edition_Year, v_countyName, round(sum(cost),2), voteCategory
from DimViewer v FORCE INDEX (v_countyIndex, catIndex, viewer_index)
join FactVote F on v.viewerSK = F.viewerSK
join DimTime t FORCE INDEX (EDY_index) on F.TimeSK = t.TimeSK
where Edition_Year = 2013 or Edition_Year = 2019
group by v_countyName, Edition_Year, voteCategory;


/* dropping indexes */
drop index EDY_index on DimTime;
drop index v_countyIndex on DimViewer;
drop index catIndex on DimViewer;
drop index viewer_index on DimViewer;


