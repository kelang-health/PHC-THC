-- OSM-PHC Cloud v2.0.4
-- Child growth / nutrition interpretation aligned to current Department of Health practice.
-- Reference bands are a version-locked snapshot of the cwhpa_referen / cwh_referen
-- tables used by JHCIS/HDC. No patient data is copied from JHCIS.
-- 0-5 y: W/A + H/A + W/H. 6-14 y: H/A + W/H (DOH 6-19 reference, B.E. 2564).
-- BMI-for-age is deliberately NOT used as a replacement because current DOH guidance
-- continues to direct 6-19 y interpretation to the 2564 H/A and W/H reference.

begin;

create table if not exists private.growth_age_reference_v204 (
  reference_version text not null,
  age_months integer not null check(age_months between 0 and 227),
  sex smallint not null check(sex in (1,2)),
  metric text not null check(metric in ('weight_for_age','height_for_age')),
  min_value numeric(8,2) not null,
  level1_high numeric(8,2) not null,
  level2_high numeric(8,2) not null,
  level3_high numeric(8,2) not null,
  level4_high numeric(8,2) not null,
  max_value numeric(8,2) not null,
  primary key(reference_version,age_months,sex,metric)
);

revoke all on private.growth_age_reference_v204 from public,anon,authenticated;

delete from private.growth_age_reference_v204 where reference_version='DOH-JHCIS-GROWTH-2026.09.12';

insert into private.growth_age_reference_v204
(reference_version,age_months,sex,metric,min_value,level1_high,level2_high,level3_high,level4_high,max_value) values
('DOH-JHCIS-GROWTH-2026.09.12',0,1,'weight_for_age',0.9,2.4,2.6,4.1,4.4,6.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,'height_for_age',38.5,46,46.9,52.7,53.7,61.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,2,'weight_for_age',0.9,2.3,2.5,4,4.2,5.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,2,'height_for_age',38,45.3,46.3,51.9,52.9,60.3),
('DOH-JHCIS-GROWTH-2026.09.12',1,1,'weight_for_age',1.5,3.3,3.5,5.4,5.8,8.1),
('DOH-JHCIS-GROWTH-2026.09.12',1,1,'height_for_age',43,50.7,51.6,57.6,58.6,66.3),
('DOH-JHCIS-GROWTH-2026.09.12',1,2,'weight_for_age',1.4,3.1,3.3,5.1,5.5,7.7),
('DOH-JHCIS-GROWTH-2026.09.12',1,2,'height_for_age',41.9,49.7,50.6,56.6,57.6,65.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,1,'weight_for_age',2.2,4.2,4.5,6.7,7.1,9.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,1,'height_for_age',46.4,54.3,55.3,61.4,62.4,70.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,2,'weight_for_age',2,3.8,4.1,6.2,6.6,9.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,2,'height_for_age',44.9,52.9,53.9,60.1,61.1,69.3),
('DOH-JHCIS-GROWTH-2026.09.12',3,1,'weight_for_age',2.7,4.9,5.2,7.6,8,10.9),
('DOH-JHCIS-GROWTH-2026.09.12',3,1,'height_for_age',49.1,57.2,58.2,64.5,65.5,73.7),
('DOH-JHCIS-GROWTH-2026.09.12',3,2,'weight_for_age',2.4,4.4,4.7,7.1,7.5,10.5),
('DOH-JHCIS-GROWTH-2026.09.12',3,2,'height_for_age',47.2,55.5,56.5,62.9,64,72.4),
('DOH-JHCIS-GROWTH-2026.09.12',4,1,'weight_for_age',3.1,5.5,5.8,8.3,8.7,11.7),
('DOH-JHCIS-GROWTH-2026.09.12',4,1,'height_for_age',51.4,59.6,60.7,67,68,76.4),
('DOH-JHCIS-GROWTH-2026.09.12',4,2,'weight_for_age',2.7,4.9,5.2,7.7,8.2,11.5),
('DOH-JHCIS-GROWTH-2026.09.12',4,2,'height_for_age',49.1,57.7,58.8,65.4,66.4,75.1),
('DOH-JHCIS-GROWTH-2026.09.12',5,1,'weight_for_age',3.4,5.9,6.2,8.8,9.3,12.5),
('DOH-JHCIS-GROWTH-2026.09.12',5,1,'height_for_age',53.2,61.6,62.6,69.1,70.1,78.6),
('DOH-JHCIS-GROWTH-2026.09.12',5,2,'weight_for_age',2.9,5.3,5.6,8.3,8.8,12.3),
('DOH-JHCIS-GROWTH-2026.09.12',5,2,'height_for_age',50.7,59.5,60.6,67.3,68.5,77.3),
('DOH-JHCIS-GROWTH-2026.09.12',6,1,'weight_for_age',3.6,6.3,6.6,9.3,9.8,13.1),
('DOH-JHCIS-GROWTH-2026.09.12',6,1,'height_for_age',54.8,63.2,64.3,70.8,71.9,80.4),
('DOH-JHCIS-GROWTH-2026.09.12',6,2,'weight_for_age',3.1,5.6,6,8.8,9.3,13),
('DOH-JHCIS-GROWTH-2026.09.12',6,2,'height_for_age',52.1,61.1,62.2,69.1,70.3,79.3),
('DOH-JHCIS-GROWTH-2026.09.12',7,1,'weight_for_age',3.8,6.6,6.9,9.8,10.3,13.7),
('DOH-JHCIS-GROWTH-2026.09.12',7,1,'height_for_age',56.1,64.7,65.8,72.4,73.5,82.2),
('DOH-JHCIS-GROWTH-2026.09.12',7,2,'weight_for_age',3.3,5.9,6.3,9.2,9.8,13.7),
('DOH-JHCIS-GROWTH-2026.09.12',7,2,'height_for_age',53.4,62.6,63.7,70.8,71.9,81.2),
('DOH-JHCIS-GROWTH-2026.09.12',8,1,'weight_for_age',4,6.8,7.2,10.1,10.7,14.3),
('DOH-JHCIS-GROWTH-2026.09.12',8,1,'height_for_age',57.3,66.1,67.2,73.9,75,83.8),
('DOH-JHCIS-GROWTH-2026.09.12',8,2,'weight_for_age',3.5,6.2,6.5,9.6,10.2,14.3),
('DOH-JHCIS-GROWTH-2026.09.12',8,2,'height_for_age',54.5,63.9,65.1,72.3,73.5,82.9),
('DOH-JHCIS-GROWTH-2026.09.12',9,1,'weight_for_age',4.1,7,7.5,10.5,11,14.8),
('DOH-JHCIS-GROWTH-2026.09.12',9,1,'height_for_age',58.5,67.4,68.5,75.3,76.5,85.4),
('DOH-JHCIS-GROWTH-2026.09.12',9,2,'weight_for_age',3.6,6.4,6.8,9.9,10.5,14.9),
('DOH-JHCIS-GROWTH-2026.09.12',9,2,'height_for_age',55.7,65.2,66.4,73.8,75,84.6),
('DOH-JHCIS-GROWTH-2026.09.12',10,1,'weight_for_age',4.3,7.3,7.7,10.8,11.4,15.2),
('DOH-JHCIS-GROWTH-2026.09.12',10,1,'height_for_age',59.6,68.6,69.7,76.7,77.9,87),
('DOH-JHCIS-GROWTH-2026.09.12',10,2,'weight_for_age',3.7,6.6,7,10.2,10.9,15.4),
('DOH-JHCIS-GROWTH-2026.09.12',10,2,'height_for_age',56.7,66.4,67.7,75.2,76.4,86.3),
('DOH-JHCIS-GROWTH-2026.09.12',11,1,'weight_for_age',4.4,7.5,7.9,11.1,11.7,15.6),
('DOH-JHCIS-GROWTH-2026.09.12',11,1,'height_for_age',60.6,69.8,71,78,79.2,88.5),
('DOH-JHCIS-GROWTH-2026.09.12',11,2,'weight_for_age',3.9,6.8,7.2,10.5,11.2,15.9),
('DOH-JHCIS-GROWTH-2026.09.12',11,2,'height_for_age',57.7,67.6,68.9,76.6,77.8,87.9),
('DOH-JHCIS-GROWTH-2026.09.12',12,1,'weight_for_age',4.5,7.6,8.1,11.4,12,16.1),
('DOH-JHCIS-GROWTH-2026.09.12',12,1,'height_for_age',61.5,70.9,72.1,79.3,80.5,90),
('DOH-JHCIS-GROWTH-2026.09.12',12,2,'weight_for_age',4,6.9,7.3,10.7,11.5,16.3),
('DOH-JHCIS-GROWTH-2026.09.12',12,2,'height_for_age',58.6,68.8,70,77.9,79.2,89.5),
('DOH-JHCIS-GROWTH-2026.09.12',13,1,'weight_for_age',4.6,7.8,8.3,11.6,12.3,16.5),
('DOH-JHCIS-GROWTH-2026.09.12',13,1,'height_for_age',62.4,72,73.2,80.6,81.8,91.5),
('DOH-JHCIS-GROWTH-2026.09.12',13,2,'weight_for_age',4.1,7.1,7.6,11.1,11.8,16.8),
('DOH-JHCIS-GROWTH-2026.09.12',13,2,'height_for_age',59.4,69.9,71.2,79.2,80.5,91),
('DOH-JHCIS-GROWTH-2026.09.12',14,1,'weight_for_age',4.7,8,8.5,11.9,12.6,16.9),
('DOH-JHCIS-GROWTH-2026.09.12',14,1,'height_for_age',63.2,73,74.2,81.8,83,92.9),
('DOH-JHCIS-GROWTH-2026.09.12',14,2,'weight_for_age',4.2,7.3,7.7,11.3,12.1,17.2),
('DOH-JHCIS-GROWTH-2026.09.12',14,2,'height_for_age',60.3,70.9,72.3,80.4,81.7,92.5),
('DOH-JHCIS-GROWTH-2026.09.12',15,1,'weight_for_age',4.8,8.2,8.6,12.2,12.8,17.3),
('DOH-JHCIS-GROWTH-2026.09.12',15,1,'height_for_age',64,74,75.2,82.9,84.2,94.3),
('DOH-JHCIS-GROWTH-2026.09.12',15,2,'weight_for_age',4.3,7.5,7.9,11.6,12.4,17.6),
('DOH-JHCIS-GROWTH-2026.09.12',15,2,'height_for_age',61.1,71.9,73.3,81.6,83,93.9),
('DOH-JHCIS-GROWTH-2026.09.12',16,1,'weight_for_age',4.9,8.3,8.8,12.4,13.1,17.7),
('DOH-JHCIS-GROWTH-2026.09.12',16,1,'height_for_age',64.7,74.9,76.2,84.1,85.4,95.7),
('DOH-JHCIS-GROWTH-2026.09.12',16,2,'weight_for_age',4.4,7.6,8.1,11.9,12.6,18.1),
('DOH-JHCIS-GROWTH-2026.09.12',16,2,'height_for_age',61.8,72.9,74.3,82.8,84.2,95.4),
('DOH-JHCIS-GROWTH-2026.09.12',17,1,'weight_for_age',5,8.5,9,12.7,13.4,18),
('DOH-JHCIS-GROWTH-2026.09.12',17,1,'height_for_age',65.4,75.9,77.2,85.2,86.5,97.1),
('DOH-JHCIS-GROWTH-2026.09.12',17,2,'weight_for_age',4.5,7.8,8.3,12.1,12.9,18.5),
('DOH-JHCIS-GROWTH-2026.09.12',17,2,'height_for_age',62.6,73.9,75.3,83.9,85.4,96.7),
('DOH-JHCIS-GROWTH-2026.09.12',18,1,'weight_for_age',5,8.7,9.2,12.9,13.7,18.4),
('DOH-JHCIS-GROWTH-2026.09.12',18,1,'height_for_age',66.1,76.8,78.1,86.3,87.7,98.4),
('DOH-JHCIS-GROWTH-2026.09.12',18,2,'weight_for_age',4.6,8,8.4,12.4,13.2,18.9),
('DOH-JHCIS-GROWTH-2026.09.12',18,2,'height_for_age',63.3,74.8,76.3,85.1,86.5,98.1),
('DOH-JHCIS-GROWTH-2026.09.12',19,1,'weight_for_age',5.1,8.8,9.3,13.2,13.9,18.8),
('DOH-JHCIS-GROWTH-2026.09.12',19,1,'height_for_age',66.7,77.6,79,87.4,88.8,99.8),
('DOH-JHCIS-GROWTH-2026.09.12',19,2,'weight_for_age',4.7,8.1,8.6,12.6,13.5,19.3),
('DOH-JHCIS-GROWTH-2026.09.12',19,2,'height_for_age',64,75.7,77.2,86.1,87.6,99.5),
('DOH-JHCIS-GROWTH-2026.09.12',20,1,'weight_for_age',5.2,9,9.5,13.4,14.2,19.2),
('DOH-JHCIS-GROWTH-2026.09.12',20,1,'height_for_age',67.3,78.5,79.9,88.4,89.8,101),
('DOH-JHCIS-GROWTH-2026.09.12',20,2,'weight_for_age',4.8,8.3,8.8,12.9,13.7,19.7),
('DOH-JHCIS-GROWTH-2026.09.12',20,2,'height_for_age',64.6,76.6,78.1,87.2,88.7,100.7),
('DOH-JHCIS-GROWTH-2026.09.12',21,1,'weight_for_age',5.3,9.1,9.7,13.7,14.5,19.6),
('DOH-JHCIS-GROWTH-2026.09.12',21,1,'height_for_age',67.9,79.3,80.7,89.4,90.9,102.4),
('DOH-JHCIS-GROWTH-2026.09.12',21,2,'weight_for_age',4.9,8.5,9,13.1,14,20.1),
('DOH-JHCIS-GROWTH-2026.09.12',21,2,'height_for_age',65.3,77.4,79,88.3,89.8,102.1),
('DOH-JHCIS-GROWTH-2026.09.12',22,1,'weight_for_age',5.4,9.3,9.8,13.9,14.7,20),
('DOH-JHCIS-GROWTH-2026.09.12',22,1,'height_for_age',68.4,80.1,81.5,90.4,91.9,103.6),
('DOH-JHCIS-GROWTH-2026.09.12',22,2,'weight_for_age',5,8.6,9.1,13.4,14.3,20.5),
('DOH-JHCIS-GROWTH-2026.09.12',22,2,'height_for_age',65.9,78.3,79.8,89.3,90.8,103.3),
('DOH-JHCIS-GROWTH-2026.09.12',23,1,'weight_for_age',5.4,9.4,10,14.2,15,20.4),
('DOH-JHCIS-GROWTH-2026.09.12',23,1,'height_for_age',69,80.9,82.3,91.4,92.9,104.9),
('DOH-JHCIS-GROWTH-2026.09.12',23,2,'weight_for_age',5.1,8.8,9.3,13.6,14.6,20.9),
('DOH-JHCIS-GROWTH-2026.09.12',23,2,'height_for_age',66.5,79.1,80.7,90.3,91.9,104.6),
('DOH-JHCIS-GROWTH-2026.09.12',24,1,'weight_for_age',5.5,9.6,10.1,14.4,15.3,20.8),
('DOH-JHCIS-GROWTH-2026.09.12',24,1,'height_for_age',69.5,80.9,82.4,91.7,93.2,106.1),
('DOH-JHCIS-GROWTH-2026.09.12',24,2,'weight_for_age',5.2,8.9,9.5,13.9,14.8,21.3),
('DOH-JHCIS-GROWTH-2026.09.12',24,2,'height_for_age',67,79.2,80.8,90.5,92.2,105.8),
('DOH-JHCIS-GROWTH-2026.09.12',25,1,'weight_for_age',5.6,9.7,10.3,14.7,15.5,21.3),
('DOH-JHCIS-GROWTH-2026.09.12',25,1,'height_for_age',69.3,81.6,83.2,92.6,94.2,106.7),
('DOH-JHCIS-GROWTH-2026.09.12',25,2,'weight_for_age',5.2,9.1,9.7,14.2,15.1,21.8),
('DOH-JHCIS-GROWTH-2026.09.12',25,2,'height_for_age',66.9,79.9,81.6,91.5,93.1,106.3),
('DOH-JHCIS-GROWTH-2026.09.12',26,1,'weight_for_age',5.6,9.9,10.5,14.9,15.8,21.7),
('DOH-JHCIS-GROWTH-2026.09.12',26,1,'height_for_age',69.7,82.4,83.9,93.6,95.2,107.8),
('DOH-JHCIS-GROWTH-2026.09.12',26,2,'weight_for_age',5.3,9.3,9.8,14.4,15.4,22.2),
('DOH-JHCIS-GROWTH-2026.09.12',26,2,'height_for_age',67.5,80.7,82.3,92.4,94.1,107.4),
('DOH-JHCIS-GROWTH-2026.09.12',27,1,'weight_for_age',5.7,10,10.6,15.2,16.1,22.1),
('DOH-JHCIS-GROWTH-2026.09.12',27,1,'height_for_age',70.2,83,84.6,94.4,96.1,109),
('DOH-JHCIS-GROWTH-2026.09.12',27,2,'weight_for_age',5.4,9.4,10,14.7,15.7,22.6),
('DOH-JHCIS-GROWTH-2026.09.12',27,2,'height_for_age',68,81.4,83.1,93.3,95,108.5),
('DOH-JHCIS-GROWTH-2026.09.12',28,1,'weight_for_age',5.8,10.1,10.8,15.4,16.3,22.5),
('DOH-JHCIS-GROWTH-2026.09.12',28,1,'height_for_age',70.7,83.7,85.4,95.3,97,110.2),
('DOH-JHCIS-GROWTH-2026.09.12',28,2,'weight_for_age',5.5,9.6,10.2,14.9,16,23.1),
('DOH-JHCIS-GROWTH-2026.09.12',28,2,'height_for_age',68.5,82.1,83.8,94.2,96,109.7),
('DOH-JHCIS-GROWTH-2026.09.12',29,1,'weight_for_age',5.8,10.3,10.9,15.7,16.6,22.9),
('DOH-JHCIS-GROWTH-2026.09.12',29,1,'height_for_age',71.1,84.4,86.1,96.2,97.9,111.3),
('DOH-JHCIS-GROWTH-2026.09.12',29,2,'weight_for_age',5.6,9.7,10.3,15.2,16.2,23.5),
('DOH-JHCIS-GROWTH-2026.09.12',29,2,'height_for_age',69,82.8,84.6,95.1,96.9,110.8),
('DOH-JHCIS-GROWTH-2026.09.12',30,1,'weight_for_age',5.9,10.4,11.1,15.9,16.9,23.3),
('DOH-JHCIS-GROWTH-2026.09.12',30,1,'height_for_age',71.5,85,86.7,97,98.7,112.4),
('DOH-JHCIS-GROWTH-2026.09.12',30,2,'weight_for_age',5.6,9.9,10.5,15.4,16.5,23.9),
('DOH-JHCIS-GROWTH-2026.09.12',30,2,'height_for_age',69.5,83.5,85.3,96,97.7,111.9),
('DOH-JHCIS-GROWTH-2026.09.12',31,1,'weight_for_age',6,10.6,11.2,16.1,17.1,23.7),
('DOH-JHCIS-GROWTH-2026.09.12',31,1,'height_for_age',71.9,85.6,87.4,97.8,99.6,113.4),
('DOH-JHCIS-GROWTH-2026.09.12',31,2,'weight_for_age',5.7,10,10.6,15.7,16.8,24.4),
('DOH-JHCIS-GROWTH-2026.09.12',31,2,'height_for_age',70,84.2,86,96.8,98.6,112.9),
('DOH-JHCIS-GROWTH-2026.09.12',32,1,'weight_for_age',6,10.7,11.3,16.3,17.4,24),
('DOH-JHCIS-GROWTH-2026.09.12',32,1,'height_for_age',72.3,86.3,88,98.6,100.4,114.4),
('DOH-JHCIS-GROWTH-2026.09.12',32,2,'weight_for_age',5.8,10.2,10.8,15.9,17.1,24.8),
('DOH-JHCIS-GROWTH-2026.09.12',32,2,'height_for_age',70.4,84.8,86.7,97.6,99.4,113.9),
('DOH-JHCIS-GROWTH-2026.09.12',33,1,'weight_for_age',6.1,10.8,11.5,16.6,17.6,24.4),
('DOH-JHCIS-GROWTH-2026.09.12',33,1,'height_for_age',72.7,86.8,88.6,99.4,101.2,115.4),
('DOH-JHCIS-GROWTH-2026.09.12',33,2,'weight_for_age',5.9,10.3,10.9,16.2,17.3,25.2),
('DOH-JHCIS-GROWTH-2026.09.12',33,2,'height_for_age',70.9,85.5,87.3,98.4,100.3,114.9),
('DOH-JHCIS-GROWTH-2026.09.12',34,1,'weight_for_age',6.1,10.9,11.6,16.8,17.8,24.8),
('DOH-JHCIS-GROWTH-2026.09.12',34,1,'height_for_age',73.1,87.4,89.2,100.2,102,116.4),
('DOH-JHCIS-GROWTH-2026.09.12',34,2,'weight_for_age',5.9,10.4,11.1,16.4,17.6,25.7),
('DOH-JHCIS-GROWTH-2026.09.12',34,2,'height_for_age',71.3,86.1,88,99.2,101.1,116),
('DOH-JHCIS-GROWTH-2026.09.12',35,1,'weight_for_age',6.2,11.1,11.7,17,18.1,25.2),
('DOH-JHCIS-GROWTH-2026.09.12',35,1,'height_for_age',73.5,88,89.8,100.9,102.7,117.4),
('DOH-JHCIS-GROWTH-2026.09.12',35,2,'weight_for_age',6,10.6,11.2,16.7,17.9,26.1),
('DOH-JHCIS-GROWTH-2026.09.12',35,2,'height_for_age',71.8,86.7,88.6,100,101.9,116.9),
('DOH-JHCIS-GROWTH-2026.09.12',36,1,'weight_for_age',6.2,11.2,11.9,17.2,18.3,25.5),
('DOH-JHCIS-GROWTH-2026.09.12',36,1,'height_for_age',73.8,88.6,90.4,101.7,103.5,118.3),
('DOH-JHCIS-GROWTH-2026.09.12',36,2,'weight_for_age',6,10.7,11.4,16.9,18.1,26.6),
('DOH-JHCIS-GROWTH-2026.09.12',36,2,'height_for_age',72.2,87.3,89.2,100.8,102.7,117.9),
('DOH-JHCIS-GROWTH-2026.09.12',37,1,'weight_for_age',6.3,11.3,12,17.4,18.6,25.9),
('DOH-JHCIS-GROWTH-2026.09.12',37,1,'height_for_age',74.2,89.1,91,102.4,104.2,119.2),
('DOH-JHCIS-GROWTH-2026.09.12',37,2,'weight_for_age',6.1,10.8,11.5,17.2,18.4,27),
('DOH-JHCIS-GROWTH-2026.09.12',37,2,'height_for_age',72.6,87.9,89.9,101.5,103.4,118.8),
('DOH-JHCIS-GROWTH-2026.09.12',38,1,'weight_for_age',6.3,11.4,12.1,17.7,18.8,26.3),
('DOH-JHCIS-GROWTH-2026.09.12',38,1,'height_for_age',74.6,89.7,91.6,103.1,105,120.1),
('DOH-JHCIS-GROWTH-2026.09.12',38,2,'weight_for_age',6.1,11,11.7,17.4,18.7,27.5),
('DOH-JHCIS-GROWTH-2026.09.12',38,2,'height_for_age',73,88.5,90.5,102.2,104.2,119.8),
('DOH-JHCIS-GROWTH-2026.09.12',39,1,'weight_for_age',6.4,11.5,12.3,17.9,19,26.7),
('DOH-JHCIS-GROWTH-2026.09.12',39,1,'height_for_age',75,90.2,92.1,103.8,105.7,121.1),
('DOH-JHCIS-GROWTH-2026.09.12',39,2,'weight_for_age',6.2,11.1,11.8,17.7,19,28),
('DOH-JHCIS-GROWTH-2026.09.12',39,2,'height_for_age',73.5,89.1,91.1,103,105,120.7),
('DOH-JHCIS-GROWTH-2026.09.12',40,1,'weight_for_age',6.4,11.7,12.4,18.1,19.3,27),
('DOH-JHCIS-GROWTH-2026.09.12',40,1,'height_for_age',75.3,90.8,92.7,104.4,106.4,121.9),
('DOH-JHCIS-GROWTH-2026.09.12',40,2,'weight_for_age',6.2,11.2,11.9,17.9,19.2,28.5),
('DOH-JHCIS-GROWTH-2026.09.12',40,2,'height_for_age',73.9,89.7,91.7,103.7,105.7,121.6),
('DOH-JHCIS-GROWTH-2026.09.12',41,1,'weight_for_age',6.5,11.8,12.5,18.3,19.5,27.4),
('DOH-JHCIS-GROWTH-2026.09.12',41,1,'height_for_age',75.7,91.3,93.2,105.1,107.1,122.8),
('DOH-JHCIS-GROWTH-2026.09.12',41,2,'weight_for_age',6.3,11.4,12.1,18.2,19.5,28.9),
('DOH-JHCIS-GROWTH-2026.09.12',41,2,'height_for_age',74.2,90.3,92.2,104.4,106.4,122.5),
('DOH-JHCIS-GROWTH-2026.09.12',42,1,'weight_for_age',6.5,11.9,12.7,18.5,19.7,27.8),
('DOH-JHCIS-GROWTH-2026.09.12',42,1,'height_for_age',76.1,91.8,93.8,105.8,107.8,123.6),
('DOH-JHCIS-GROWTH-2026.09.12',42,2,'weight_for_age',6.3,11.5,12.2,18.4,19.8,29.4),
('DOH-JHCIS-GROWTH-2026.09.12',42,2,'height_for_age',74.6,90.8,92.8,105.1,107.2,123.4),
('DOH-JHCIS-GROWTH-2026.09.12',43,1,'weight_for_age',6.6,12,12.8,18.7,20,28.2),
('DOH-JHCIS-GROWTH-2026.09.12',43,1,'height_for_age',76.4,92.3,94.3,106.4,108.5,124.5),
('DOH-JHCIS-GROWTH-2026.09.12',43,2,'weight_for_age',6.4,11.6,12.4,18.7,20.1,29.9),
('DOH-JHCIS-GROWTH-2026.09.12',43,2,'height_for_age',75,91.4,93.4,105.8,107.9,124.3),
('DOH-JHCIS-GROWTH-2026.09.12',44,1,'weight_for_age',6.6,12.1,12.9,19,20.2,28.6),
('DOH-JHCIS-GROWTH-2026.09.12',44,1,'height_for_age',76.8,92.9,94.9,107.1,109.1,125.3),
('DOH-JHCIS-GROWTH-2026.09.12',44,2,'weight_for_age',6.4,11.7,12.5,18.9,20.4,30.4),
('DOH-JHCIS-GROWTH-2026.09.12',44,2,'height_for_age',75.4,91.9,94,106.5,108.6,125.2),
('DOH-JHCIS-GROWTH-2026.09.12',45,1,'weight_for_age',6.7,12.3,13,19.2,20.5,29),
('DOH-JHCIS-GROWTH-2026.09.12',45,1,'height_for_age',77.1,93.4,95.4,107.7,109.8,126.1),
('DOH-JHCIS-GROWTH-2026.09.12',45,2,'weight_for_age',6.4,11.9,12.6,19.2,20.7,30.9),
('DOH-JHCIS-GROWTH-2026.09.12',45,2,'height_for_age',75.8,92.4,94.5,107.2,109.3,126.1),
('DOH-JHCIS-GROWTH-2026.09.12',46,1,'weight_for_age',6.7,12.4,13.2,19.4,20.7,29.4),
('DOH-JHCIS-GROWTH-2026.09.12',46,1,'height_for_age',77.5,93.9,95.9,108.4,110.4,126.9),
('DOH-JHCIS-GROWTH-2026.09.12',46,2,'weight_for_age',6.5,12,12.8,19.4,20.9,31.4),
('DOH-JHCIS-GROWTH-2026.09.12',46,2,'height_for_age',76.2,93,95.1,107.9,110,126.9),
('DOH-JHCIS-GROWTH-2026.09.12',47,1,'weight_for_age',6.8,12.5,13.3,19.6,20.9,29.8),
('DOH-JHCIS-GROWTH-2026.09.12',47,1,'height_for_age',77.8,94.3,96.4,109,111.1,127.7),
('DOH-JHCIS-GROWTH-2026.09.12',47,2,'weight_for_age',6.5,12.1,12.9,19.7,21.2,32),
('DOH-JHCIS-GROWTH-2026.09.12',47,2,'height_for_age',76.5,93.5,95.6,108.5,110.7,127.7),
('DOH-JHCIS-GROWTH-2026.09.12',48,1,'weight_for_age',6.8,12.6,13.4,19.8,21.2,30.2),
('DOH-JHCIS-GROWTH-2026.09.12',48,1,'height_for_age',78.2,94.8,96.9,109.6,111.7,128.5),
('DOH-JHCIS-GROWTH-2026.09.12',48,2,'weight_for_age',6.6,12.2,13,19.9,21.5,32.5),
('DOH-JHCIS-GROWTH-2026.09.12',48,2,'height_for_age',76.9,94,96.2,109.2,111.3,128.5),
('DOH-JHCIS-GROWTH-2026.09.12',49,1,'weight_for_age',6.9,12.7,13.6,20.1,21.4,30.6),
('DOH-JHCIS-GROWTH-2026.09.12',49,1,'height_for_age',78.5,95.3,97.5,110.2,112.4,129.3),
('DOH-JHCIS-GROWTH-2026.09.12',49,2,'weight_for_age',6.6,12.3,13.2,20.2,21.8,33),
('DOH-JHCIS-GROWTH-2026.09.12',49,2,'height_for_age',77.2,94.5,96.7,109.9,112,129.4),
('DOH-JHCIS-GROWTH-2026.09.12',50,1,'weight_for_age',6.9,12.8,13.7,20.3,21.7,31),
('DOH-JHCIS-GROWTH-2026.09.12',50,1,'height_for_age',78.8,95.8,97.9,110.9,113,130.1),
('DOH-JHCIS-GROWTH-2026.09.12',50,2,'weight_for_age',6.6,12.5,13.3,20.4,22.1,33.5),
('DOH-JHCIS-GROWTH-2026.09.12',50,2,'height_for_age',77.6,95,97.2,110.5,112.7,130.2),
('DOH-JHCIS-GROWTH-2026.09.12',51,1,'weight_for_age',6.9,13,13.8,20.5,21.9,31.4),
('DOH-JHCIS-GROWTH-2026.09.12',51,1,'height_for_age',79.2,96.3,98.4,111.4,113.6,130.8),
('DOH-JHCIS-GROWTH-2026.09.12',51,2,'weight_for_age',6.7,12.6,13.4,20.7,22.4,34.1),
('DOH-JHCIS-GROWTH-2026.09.12',51,2,'height_for_age',77.9,95.5,97.7,111.1,113.3,131),
('DOH-JHCIS-GROWTH-2026.09.12',52,1,'weight_for_age',7,13.1,13.9,20.7,22.2,31.8),
('DOH-JHCIS-GROWTH-2026.09.12',52,1,'height_for_age',79.5,96.8,99,112.1,114.2,131.6),
('DOH-JHCIS-GROWTH-2026.09.12',52,2,'weight_for_age',6.7,12.7,13.6,20.9,22.6,34.6),
('DOH-JHCIS-GROWTH-2026.09.12',52,2,'height_for_age',78.3,96,98.3,111.7,114,131.8),
('DOH-JHCIS-GROWTH-2026.09.12',53,1,'weight_for_age',7,13.2,14.1,20.9,22.4,32.2),
('DOH-JHCIS-GROWTH-2026.09.12',53,1,'height_for_age',79.8,97.3,99.4,112.7,114.9,132.4),
('DOH-JHCIS-GROWTH-2026.09.12',53,2,'weight_for_age',6.7,12.8,13.7,21.2,22.9,35.1),
('DOH-JHCIS-GROWTH-2026.09.12',53,2,'height_for_age',78.6,96.5,98.8,112.4,114.6,132.6),
('DOH-JHCIS-GROWTH-2026.09.12',54,1,'weight_for_age',7.1,13.3,14.2,21.2,22.7,32.7),
('DOH-JHCIS-GROWTH-2026.09.12',54,1,'height_for_age',80.2,97.7,100,113.3,115.5,133.2),
('DOH-JHCIS-GROWTH-2026.09.12',54,2,'weight_for_age',6.8,12.9,13.8,21.5,23.2,35.6),
('DOH-JHCIS-GROWTH-2026.09.12',54,2,'height_for_age',79,97,99.3,113,115.2,133.4),
('DOH-JHCIS-GROWTH-2026.09.12',55,1,'weight_for_age',7.1,13.4,14.3,21.4,22.9,33.1),
('DOH-JHCIS-GROWTH-2026.09.12',55,1,'height_for_age',80.5,98.2,100.4,113.9,116.1,133.9),
('DOH-JHCIS-GROWTH-2026.09.12',55,2,'weight_for_age',6.8,13.1,14,21.7,23.5,36.1),
('DOH-JHCIS-GROWTH-2026.09.12',55,2,'height_for_age',79.3,97.5,99.8,113.6,115.9,134.2),
('DOH-JHCIS-GROWTH-2026.09.12',56,1,'weight_for_age',7.1,13.5,14.4,21.6,23.2,33.5),
('DOH-JHCIS-GROWTH-2026.09.12',56,1,'height_for_age',80.8,98.7,100.9,114.5,116.7,134.7),
('DOH-JHCIS-GROWTH-2026.09.12',56,2,'weight_for_age',6.8,13.2,14.1,22,23.8,36.7),
('DOH-JHCIS-GROWTH-2026.09.12',56,2,'height_for_age',79.6,98,100.3,114.2,116.5,134.9),
('DOH-JHCIS-GROWTH-2026.09.12',57,1,'weight_for_age',7.2,13.6,14.5,21.8,23.4,33.9),
('DOH-JHCIS-GROWTH-2026.09.12',57,1,'height_for_age',81.2,99.2,101.4,115.1,117.4,135.4),
('DOH-JHCIS-GROWTH-2026.09.12',57,2,'weight_for_age',6.9,13.3,14.2,22.2,24.1,37.2),
('DOH-JHCIS-GROWTH-2026.09.12',57,2,'height_for_age',79.9,98.4,100.7,114.8,117.1,135.7),
('DOH-JHCIS-GROWTH-2026.09.12',58,1,'weight_for_age',7.2,13.7,14.7,22.1,23.7,34.4),
('DOH-JHCIS-GROWTH-2026.09.12',58,1,'height_for_age',81.5,99.6,101.9,115.7,118,136.2),
('DOH-JHCIS-GROWTH-2026.09.12',58,2,'weight_for_age',6.9,13.4,14.4,22.5,24.4,37.7),
('DOH-JHCIS-GROWTH-2026.09.12',58,2,'height_for_age',80.3,98.9,101.2,115.4,117.7,136.5),
('DOH-JHCIS-GROWTH-2026.09.12',59,1,'weight_for_age',7.2,13.9,14.8,22.3,23.9,34.8),
('DOH-JHCIS-GROWTH-2026.09.12',59,1,'height_for_age',81.8,100.1,102.4,116.3,118.6,137),
('DOH-JHCIS-GROWTH-2026.09.12',59,2,'weight_for_age',7,13.5,14.5,22.7,24.6,38.3),
('DOH-JHCIS-GROWTH-2026.09.12',59,2,'height_for_age',80.6,99.4,101.7,116,118.3,137.2),
('DOH-JHCIS-GROWTH-2026.09.12',60,1,'weight_for_age',7.3,14,14.9,22.5,24.2,35.2),
('DOH-JHCIS-GROWTH-2026.09.12',60,1,'height_for_age',82.2,100.6,102.9,116.9,119.2,137.8),
('DOH-JHCIS-GROWTH-2026.09.12',60,2,'weight_for_age',7,13.6,14.6,23,24.9,38.8),
('DOH-JHCIS-GROWTH-2026.09.12',60,2,'height_for_age',80.9,99.8,102.2,116.6,118.9,138),
('DOH-JHCIS-GROWTH-2026.09.12',72,1,'weight_for_age',0,15.4,16.5,25.4,27.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',72,1,'height_for_age',0,105.3,107.6,121.3,123.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',72,2,'weight_for_age',0,14.9,16,24.7,26.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',72,2,'height_for_age',0,105.1,107.3,120.8,123,300),
('DOH-JHCIS-GROWTH-2026.09.12',73,1,'weight_for_age',0,15.5,16.6,25.6,27.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',73,1,'height_for_age',0,105.8,108,121.9,124.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',73,2,'weight_for_age',0,15.1,16.2,25,26.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',73,2,'height_for_age',0,105.5,107.7,121.3,123.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',74,1,'weight_for_age',0,15.7,16.8,25.9,27.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',74,1,'height_for_age',0,106.2,108.5,122.4,124.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',74,2,'weight_for_age',0,15.2,16.3,25.3,27.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',74,2,'height_for_age',0,106,108.2,121.9,124.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',75,1,'weight_for_age',0,15.8,16.9,26.2,28.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',75,1,'height_for_age',0,106.6,108.9,122.9,125.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',75,2,'weight_for_age',0,15.3,16.5,25.6,27.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',75,2,'height_for_age',0,106.4,108.6,122.4,124.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',76,1,'weight_for_age',0,15.9,17,26.5,28.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',76,1,'height_for_age',0,107.1,109.4,123.5,125.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',76,2,'weight_for_age',0,15.4,16.6,26,28,300),
('DOH-JHCIS-GROWTH-2026.09.12',76,2,'height_for_age',0,106.9,109.1,122.9,125.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',77,1,'weight_for_age',0,16,17.2,26.7,28.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',77,1,'height_for_age',0,107.4,109.8,124,126.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',77,2,'weight_for_age',0,15.6,16.8,26.4,28.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',77,2,'height_for_age',0,107.3,109.5,123.4,125.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',78,1,'weight_for_age',0,16.1,17.3,27,29.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',78,1,'height_for_age',0,107.8,110.2,124.5,126.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',78,2,'weight_for_age',0,15.7,16.9,26.8,28.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',78,2,'height_for_age',0,107.7,109.9,123.9,126.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',79,1,'weight_for_age',0,16.3,17.6,27.4,29.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',79,1,'height_for_age',0,108.2,110.6,125,127.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',79,2,'weight_for_age',0,15.8,17,27.1,29.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',79,2,'height_for_age',0,108,110.4,124.4,126.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',80,1,'weight_for_age',0,16.4,17.6,27.6,29.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',80,1,'height_for_age',0,108.8,111.1,125.5,127.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',80,2,'weight_for_age',0,15.9,17.1,27.4,29.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',80,2,'height_for_age',0,108.4,110.8,124.9,127.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',81,1,'weight_for_age',0,16.6,17.8,27.9,30.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',81,1,'height_for_age',0,109.1,111.5,126,128.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',81,2,'weight_for_age',0,16.1,17.3,27.8,30,300),
('DOH-JHCIS-GROWTH-2026.09.12',81,2,'height_for_age',0,108.7,111.1,125.4,127.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',82,1,'weight_for_age',0,16.7,17.9,28.2,30.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',82,1,'height_for_age',0,109.5,111.9,126.4,128.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',82,2,'weight_for_age',0,16.2,17.4,28.1,30.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',82,2,'height_for_age',0,109.1,111.5,125.9,128.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',83,1,'weight_for_age',0,16.8,18,28.5,30.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',83,1,'height_for_age',0,109.9,112.3,126.9,129.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',83,2,'weight_for_age',0,16.3,17.5,28.4,30.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',83,2,'height_for_age',0,109.5,111.9,126.4,128.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',84,1,'weight_for_age',0,17,18.2,28.8,31,300),
('DOH-JHCIS-GROWTH-2026.09.12',84,1,'height_for_age',0,110.3,112.7,127.4,129.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',84,2,'weight_for_age',0,16.4,17.6,28.7,31.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',84,2,'height_for_age',0,109.8,112.3,126.8,129.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',85,1,'weight_for_age',0,17.1,18.3,29,31.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',85,1,'height_for_age',0,110.7,113.1,127.8,130.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',85,2,'weight_for_age',0,16.6,17.8,29.1,31.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',85,2,'height_for_age',0,110.2,112.7,127.3,129.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',86,1,'weight_for_age',0,17.2,18.5,29.3,31.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',86,1,'height_for_age',0,111,113.5,128.3,130.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',86,2,'weight_for_age',0,16.7,18,29.4,31.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',86,2,'height_for_age',0,110.6,113.1,127.8,130.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',87,1,'weight_for_age',0,17.4,18.7,29.6,32,300),
('DOH-JHCIS-GROWTH-2026.09.12',87,1,'height_for_age',0,111.4,113.9,128.8,131.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',87,2,'weight_for_age',0,16.8,18.1,29.7,32.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',87,2,'height_for_age',0,110.9,113.4,128.2,130.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',88,1,'weight_for_age',0,17.5,18.8,29.9,32.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',88,1,'height_for_age',0,111.8,114.3,129.3,131.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',88,2,'weight_for_age',0,16.9,18.2,30.1,32.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',88,2,'height_for_age',0,111.3,113.8,128.6,131.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',89,1,'weight_for_age',0,17.6,18.9,30.2,32.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',89,1,'height_for_age',0,112.2,114.7,129.8,132.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',89,2,'weight_for_age',0,17,18.3,30.4,33,300),
('DOH-JHCIS-GROWTH-2026.09.12',89,2,'height_for_age',0,111.7,114.2,129.1,131.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',90,1,'weight_for_age',0,17.7,19,30.4,32.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',90,1,'height_for_age',0,112.5,115,130.3,132.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',90,2,'weight_for_age',0,17.2,18.5,30.7,33.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',90,2,'height_for_age',0,112.1,114.6,129.5,132,300),
('DOH-JHCIS-GROWTH-2026.09.12',91,1,'weight_for_age',0,17.9,19.2,30.7,33.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',91,1,'height_for_age',0,112.9,115.4,130.8,133.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',91,2,'weight_for_age',0,17.3,18.6,31.1,33.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',91,2,'height_for_age',0,112.4,114.9,130,132.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',92,1,'weight_for_age',0,18,19.3,30.9,33.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',92,1,'height_for_age',0,113.3,115.8,131.2,133.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',92,2,'weight_for_age',0,17.4,18.7,31.3,34.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',92,2,'height_for_age',0,112.8,115.3,130.5,133,300),
('DOH-JHCIS-GROWTH-2026.09.12',93,1,'weight_for_age',0,18.1,19.4,31.2,33.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',93,1,'height_for_age',0,113.6,116.2,131.7,134.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',93,2,'weight_for_age',0,17.5,18.8,31.7,34.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',93,2,'height_for_age',0,113.2,115.7,131,133.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',94,1,'weight_for_age',0,18.2,19.5,31.5,34.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',94,1,'height_for_age',0,114,116.6,132.2,134.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',94,2,'weight_for_age',0,17.6,19,32,34.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',94,2,'height_for_age',0,113.6,116.1,131.5,134,300),
('DOH-JHCIS-GROWTH-2026.09.12',95,1,'weight_for_age',0,18.3,19.7,31.8,34.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',95,1,'height_for_age',0,114.4,117,132.7,135.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',95,2,'weight_for_age',0,17.7,19.1,32.3,35.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',95,2,'height_for_age',0,114,116.5,132,134.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',96,1,'weight_for_age',0,18.5,19.9,32.2,34.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',96,1,'height_for_age',0,114.7,117.3,133.2,135.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',96,2,'weight_for_age',0,17.8,19.2,32.5,35.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',96,2,'height_for_age',0,114.3,116.9,132.5,135.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',97,1,'weight_for_age',0,18.6,20,32.6,35.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',97,1,'height_for_age',0,115.1,117.7,133.6,136.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',97,2,'weight_for_age',0,17.9,19.3,32.9,35.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',97,2,'height_for_age',0,114.7,117.3,133,135.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',98,1,'weight_for_age',0,18.7,20.1,33,35.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',98,1,'height_for_age',0,115.3,118,134,136.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',98,2,'weight_for_age',0,18.1,19.5,33.3,36.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',98,2,'height_for_age',0,115.1,117.7,133.5,136.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',99,1,'weight_for_age',0,18.8,20.2,33.3,36.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',99,1,'height_for_age',0,115.8,118.4,134.5,137.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',99,2,'weight_for_age',0,18.1,19.6,33.6,36.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',99,2,'height_for_age',0,115.5,118.1,134.1,136.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',100,1,'weight_for_age',0,18.8,20.3,33.7,36.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',100,1,'height_for_age',0,116,118.7,134.9,137.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',100,2,'weight_for_age',0,18.2,19.8,34.1,37.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',100,2,'height_for_age',0,115.9,118.5,134.7,137.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',101,1,'weight_for_age',0,18.9,20.5,34,37,300),
('DOH-JHCIS-GROWTH-2026.09.12',101,1,'height_for_age',0,116.5,119.1,135.3,138,300),
('DOH-JHCIS-GROWTH-2026.09.12',101,2,'weight_for_age',0,18.3,19.9,34.5,37.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',101,2,'height_for_age',0,116.3,118.9,135.2,137.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',102,1,'weight_for_age',0,19,20.6,34.4,37.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',102,1,'height_for_age',0,116.9,119.6,135.7,138.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',102,2,'weight_for_age',0,18.5,20.1,34.9,38.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',102,2,'height_for_age',0,116.7,119.4,135.7,138.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',103,1,'weight_for_age',0,19.1,20.7,34.8,37.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',103,1,'height_for_age',0,117.2,119.9,136.1,138.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',103,2,'weight_for_age',0,18.6,20.2,35.4,38.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',103,2,'height_for_age',0,117.1,119.8,136.3,139.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',104,1,'weight_for_age',0,19.2,20.8,35.1,38.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',104,1,'height_for_age',0,117.5,120.3,136.6,139.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',104,2,'weight_for_age',0,18.8,20.4,35.8,39.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',104,2,'height_for_age',0,117.5,120.2,136.9,139.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',105,1,'weight_for_age',0,19.3,20.9,35.5,38.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',105,1,'height_for_age',0,117.8,120.6,137,139.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',105,2,'weight_for_age',0,18.9,20.6,36.2,39.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',105,2,'height_for_age',0,117.8,120.6,137.4,140.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',106,1,'weight_for_age',0,19.4,21.1,35.9,39.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',106,1,'height_for_age',0,118.2,121,137.4,140.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',106,2,'weight_for_age',0,19,20.7,36.7,40.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',106,2,'height_for_age',0,118.2,121,138,140.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',107,1,'weight_for_age',0,19.6,21.3,36.2,39.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',107,1,'height_for_age',0,118.6,121.4,137.8,140.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',107,2,'weight_for_age',0,19.2,20.9,37,40.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',107,2,'height_for_age',0,118.6,121.4,138.6,141.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',108,1,'weight_for_age',0,19.7,21.4,36.6,39.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',108,1,'height_for_age',0,118.9,121.7,138.3,140.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',108,2,'weight_for_age',0,19.3,21.1,37.4,41.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',108,2,'height_for_age',0,119,121.8,139.1,142.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',109,1,'weight_for_age',0,19.8,21.5,36.9,40.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',109,1,'height_for_age',0,119.3,122.1,138.7,141.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',109,2,'weight_for_age',0,19.5,21.3,37.8,41.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',109,2,'height_for_age',0,119.4,122.2,139.7,142.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',110,1,'weight_for_age',0,19.9,21.7,37.3,40.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',110,1,'height_for_age',0,119.6,122.5,139.1,141.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',110,2,'weight_for_age',0,19.6,21.4,38.2,42,300),
('DOH-JHCIS-GROWTH-2026.09.12',110,2,'height_for_age',0,119.8,122.6,140.3,143.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',111,1,'weight_for_age',0,20.1,21.9,37.6,41,300),
('DOH-JHCIS-GROWTH-2026.09.12',111,1,'height_for_age',0,120,122.9,139.6,142.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',111,2,'weight_for_age',0,19.6,21.5,38.6,42.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',111,2,'height_for_age',0,120.2,123,140.8,143.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',112,1,'weight_for_age',0,20.2,22,38,41.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',112,1,'height_for_age',0,120.3,123.2,140,142.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',112,2,'weight_for_age',0,19.8,21.7,39,42.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',112,2,'height_for_age',0,120.6,123.4,141.4,144.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',113,1,'weight_for_age',0,20.3,22.2,38.4,41.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',113,1,'height_for_age',0,120.7,123.6,140.4,143.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',113,2,'weight_for_age',0,19.9,21.9,39.4,43.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',113,2,'height_for_age',0,121,123.9,142,145.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',114,1,'weight_for_age',0,20.5,22.4,38.7,42.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',114,1,'height_for_age',0,121.1,124,140.8,143.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',114,2,'weight_for_age',0,20.1,22.1,39.8,43.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',114,2,'height_for_age',0,121.5,124.4,142.6,145.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',115,1,'weight_for_age',0,20.6,22.6,39.1,42.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',115,1,'height_for_age',0,121.4,124.3,141.3,144,300),
('DOH-JHCIS-GROWTH-2026.09.12',115,2,'weight_for_age',0,20.2,22.2,40.2,44.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',115,2,'height_for_age',0,121.9,124.8,143.1,146.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',116,1,'weight_for_age',0,20.8,22.8,39.4,42.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',116,1,'height_for_age',0,121.9,124.7,141.7,144.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',116,2,'weight_for_age',0,20.4,22.5,40.6,44.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',116,2,'height_for_age',0,122.3,125.2,143.7,146.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',117,1,'weight_for_age',0,20.9,22.9,39.8,43.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',117,1,'height_for_age',0,122.1,125,142.1,144.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',117,2,'weight_for_age',0,20.6,22.7,41,45,300),
('DOH-JHCIS-GROWTH-2026.09.12',117,2,'height_for_age',0,122.7,125.6,144.2,147.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',118,1,'weight_for_age',0,21.1,23.1,40.1,43.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',118,1,'height_for_age',0,122.5,125.4,142.5,145.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',118,2,'weight_for_age',0,20.8,22.9,41.3,45.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',118,2,'height_for_age',0,123.1,126.1,144.8,148.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',119,1,'weight_for_age',0,21.3,23.3,40.5,44.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',119,1,'height_for_age',0,122.9,125.8,142.9,145.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',119,2,'weight_for_age',0,21,23.1,41.7,45.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',119,2,'height_for_age',0,123.6,126.6,145.5,148.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',120,1,'weight_for_age',0,21.4,23.5,40.8,44.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',120,1,'height_for_age',0,123.2,126.1,143.4,146.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',120,2,'weight_for_age',0,21.2,23.3,42.1,46.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',120,2,'height_for_age',0,124,127,146.1,149.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',121,1,'weight_for_age',0,21.6,23.7,41.2,44.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',121,1,'height_for_age',0,123.6,126.5,143.8,146.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',121,2,'weight_for_age',0,21.4,23.6,42.5,46.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',121,2,'height_for_age',0,124.4,127.4,146.7,150,300),
('DOH-JHCIS-GROWTH-2026.09.12',122,1,'weight_for_age',0,21.7,23.8,41.5,45.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',122,1,'height_for_age',0,123.9,126.8,144.2,147.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',122,2,'weight_for_age',0,21.6,23.8,42.9,47,300),
('DOH-JHCIS-GROWTH-2026.09.12',122,2,'height_for_age',0,124.9,128,147.3,150.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',123,1,'weight_for_age',0,21.9,24,41.8,45.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',123,1,'height_for_age',0,124.5,127.3,144.7,147.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',123,2,'weight_for_age',0,21.8,24,43.3,47.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',123,2,'height_for_age',0,125.2,128.4,147.9,151.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',124,1,'weight_for_age',0,22.1,24.2,42.2,46,300),
('DOH-JHCIS-GROWTH-2026.09.12',124,1,'height_for_age',0,124.7,127.6,145.1,148.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',124,2,'weight_for_age',0,21.9,24.3,43.6,47.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',124,2,'height_for_age',0,125.7,128.9,148.5,151.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',125,1,'weight_for_age',0,22.2,24.3,42.5,46.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',125,1,'height_for_age',0,125.1,128,145.6,148.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',125,2,'weight_for_age',0,22.1,24.5,44,48.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',125,2,'height_for_age',0,126.1,129.4,149.1,152.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',126,1,'weight_for_age',0,22.4,24.6,42.8,46.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',126,1,'height_for_age',0,125.4,128.3,146.1,149.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',126,2,'weight_for_age',0,22.3,24.7,44.4,48.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',126,2,'height_for_age',0,126.6,129.9,149.7,153,300),
('DOH-JHCIS-GROWTH-2026.09.12',127,1,'weight_for_age',0,22.5,24.7,43.1,47,300),
('DOH-JHCIS-GROWTH-2026.09.12',127,1,'height_for_age',0,125.8,128.7,146.6,149.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',127,2,'weight_for_age',0,22.4,24.9,44.7,48.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',127,2,'height_for_age',0,127.1,130.4,150.2,153.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',128,1,'weight_for_age',0,22.7,24.9,43.5,47.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',128,1,'height_for_age',0,126.2,129,147.2,150.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',128,2,'weight_for_age',0,22.6,25.1,45.1,49.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',128,2,'height_for_age',0,127.5,130.8,150.7,154,300),
('DOH-JHCIS-GROWTH-2026.09.12',129,1,'weight_for_age',0,22.8,25,43.9,48,300),
('DOH-JHCIS-GROWTH-2026.09.12',129,1,'height_for_age',0,126.5,129.4,147.7,150.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',129,2,'weight_for_age',0,22.8,25.4,45.5,49.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',129,2,'height_for_age',0,128,131.4,151.2,154.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',130,1,'weight_for_age',0,22.8,25.2,44.3,48.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',130,1,'height_for_age',0,126.8,129.7,148.3,151.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',130,2,'weight_for_age',0,23,25.6,45.8,49.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',130,2,'height_for_age',0,128.5,131.9,151.7,155,300),
('DOH-JHCIS-GROWTH-2026.09.12',131,1,'weight_for_age',0,23,25.4,44.8,48.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',131,1,'height_for_age',0,127.1,130.1,148.9,152.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',131,2,'weight_for_age',0,23.1,25.7,46.1,50.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',131,2,'height_for_age',0,128.9,132.3,152.2,155.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',132,1,'weight_for_age',0,23.1,25.5,45.2,49.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',132,1,'height_for_age',0,127.4,130.4,149.4,152.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',132,2,'weight_for_age',0,23.3,26,46.5,50.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',132,2,'height_for_age',0,129.4,132.8,152.6,155.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',133,1,'weight_for_age',0,23.3,25.7,45.6,49.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',133,1,'height_for_age',0,127.8,130.8,150.1,153.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',133,2,'weight_for_age',0,23.4,26.2,46.8,50.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',133,2,'height_for_age',0,129.9,133.3,153,156.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',134,1,'weight_for_age',0,23.4,25.9,46.1,50.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',134,1,'height_for_age',0,128,131.1,150.7,154.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',134,2,'weight_for_age',0,23.6,26.4,47.1,51.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',134,2,'height_for_age',0,130.4,133.8,153.3,156.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',135,1,'weight_for_age',0,23.6,26.1,46.4,50.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',135,1,'height_for_age',0,128.3,131.4,151.3,154.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',135,2,'weight_for_age',0,23.9,26.7,47.4,51.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',135,2,'height_for_age',0,130.9,134.2,153.7,156.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',136,1,'weight_for_age',0,23.7,26.2,46.8,51.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',136,1,'height_for_age',0,128.8,131.9,151.9,155.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',136,2,'weight_for_age',0,24.1,27,47.8,51.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',136,2,'height_for_age',0,131.4,134.7,154.1,157.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',137,1,'weight_for_age',0,23.9,26.4,47.2,51.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',137,1,'height_for_age',0,129,132.2,152.5,156.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',137,2,'weight_for_age',0,24.3,27.2,48.1,52.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',137,2,'height_for_age',0,131.8,135.1,154.4,157.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',138,1,'weight_for_age',0,24.1,26.7,47.6,51.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',138,1,'height_for_age',0,129.3,132.5,153.2,156.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',138,2,'weight_for_age',0,24.6,27.5,48.4,52.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',138,2,'height_for_age',0,132.3,135.6,154.7,157.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',139,1,'weight_for_age',0,24.3,26.9,48,52.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',139,1,'height_for_age',0,129.7,133,153.8,157.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',139,2,'weight_for_age',0,24.9,27.8,48.7,52.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',139,2,'height_for_age',0,132.8,136.1,155.1,158.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',140,1,'weight_for_age',0,24.5,27.1,48.4,52.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',140,1,'height_for_age',0,130,133.3,154.4,158.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',140,2,'weight_for_age',0,25.1,28,49,53,300),
('DOH-JHCIS-GROWTH-2026.09.12',140,2,'height_for_age',0,133.3,136.6,155.5,158.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',141,1,'weight_for_age',0,24.6,27.3,48.8,53.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',141,1,'height_for_age',0,130.4,133.8,155,158.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',141,2,'weight_for_age',0,25.4,28.4,49.3,53.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',141,2,'height_for_age',0,133.8,137.1,155.8,158.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',142,1,'weight_for_age',0,24.6,27.4,49.2,53.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',142,1,'height_for_age',0,130.8,134.2,155.7,159.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',142,2,'weight_for_age',0,25.7,28.7,49.6,53.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',142,2,'height_for_age',0,134.3,137.7,156.2,159,300),
('DOH-JHCIS-GROWTH-2026.09.12',143,1,'weight_for_age',0,25,27.8,49.6,54.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',143,1,'height_for_age',0,131.1,134.5,156.3,160,300),
('DOH-JHCIS-GROWTH-2026.09.12',143,2,'weight_for_age',0,26,29,49.9,53.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',143,2,'height_for_age',0,134.8,138.2,156.5,159.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',144,1,'weight_for_age',0,25.2,28,50,54.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',144,1,'height_for_age',0,131.5,135,156.9,160.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',144,2,'weight_for_age',0,26.3,29.3,50.2,54,300),
('DOH-JHCIS-GROWTH-2026.09.12',144,2,'height_for_age',0,135.3,138.7,156.9,159.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',145,1,'weight_for_age',0,25.4,28.3,50.4,54.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',145,1,'height_for_age',0,131.8,135.4,157.5,161.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',145,2,'weight_for_age',0,26.6,29.6,50.5,54.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',145,2,'height_for_age',0,135.8,139.1,157.2,159.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',146,1,'weight_for_age',0,25.6,28.5,50.8,55.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',146,1,'height_for_age',0,132.2,135.9,158.2,161.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',146,2,'weight_for_age',0,26.9,29.9,50.8,54.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',146,2,'height_for_age',0,136.3,139.6,157.5,160.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',147,1,'weight_for_age',0,25.8,28.7,51.2,55.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',147,1,'height_for_age',0,132.6,136.3,158.8,162.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',147,2,'weight_for_age',0,27.2,30.3,51,54.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',147,2,'height_for_age',0,136.7,140,157.8,160.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',148,1,'weight_for_age',0,26,29,51.5,56,300),
('DOH-JHCIS-GROWTH-2026.09.12',148,1,'height_for_age',0,133.1,136.8,159.4,163.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',148,2,'weight_for_age',0,27.5,30.6,51.2,55,300),
('DOH-JHCIS-GROWTH-2026.09.12',148,2,'height_for_age',0,137.2,140.5,158.1,160.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',149,1,'weight_for_age',0,26.3,29.3,51.9,56.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',149,1,'height_for_age',0,133.5,137.3,160,163.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',149,2,'weight_for_age',0,27.8,30.9,51.6,55.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',149,2,'height_for_age',0,137.6,140.9,158.4,160.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',150,1,'weight_for_age',0,26.5,29.6,52.3,56.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',150,1,'height_for_age',0,133.9,137.7,160.7,164.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',150,2,'weight_for_age',0,28.1,31.2,51.8,55.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',150,2,'height_for_age',0,138,141.3,158.7,161.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',151,1,'weight_for_age',0,26.8,29.9,52.7,57.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',151,1,'height_for_age',0,134.4,138.3,161.3,165.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',151,2,'weight_for_age',0,28.4,31.5,52,55.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',151,2,'height_for_age',0,138.4,141.6,159,161.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',152,1,'weight_for_age',0,26.9,30.1,53,57.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',152,1,'height_for_age',0,134.9,138.8,161.9,165.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',152,2,'weight_for_age',0,28.7,31.8,52.2,55.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',152,2,'height_for_age',0,138.8,142,159.2,161.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',153,1,'weight_for_age',0,27.2,30.4,53.4,57.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',153,1,'height_for_age',0,135.3,139.2,162.6,166.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',153,2,'weight_for_age',0,29,32.1,52.5,56.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',153,2,'height_for_age',0,139.2,142.4,159.5,162,300),
('DOH-JHCIS-GROWTH-2026.09.12',154,1,'weight_for_age',0,27.5,30.8,53.9,58.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',154,1,'height_for_age',0,135.7,139.8,163.2,166.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',154,2,'weight_for_age',0,29.2,32.3,52.7,56.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',154,2,'height_for_age',0,139.5,142.7,159.7,162.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',155,1,'weight_for_age',0,27.8,31.1,54.2,58.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',155,1,'height_for_age',0,136.2,140.3,163.8,167.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',155,2,'weight_for_age',0,29.5,32.6,52.9,56.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',155,2,'height_for_age',0,140,143.1,160,162.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',156,1,'weight_for_age',0,28.1,31.5,54.6,58.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',156,1,'height_for_age',0,136.7,140.8,164.4,168.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',156,2,'weight_for_age',0,29.8,32.9,53.1,56.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',156,2,'height_for_age',0,140.4,143.4,160.2,162.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',157,1,'weight_for_age',0,28.4,31.8,54.9,59.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',157,1,'height_for_age',0,137.2,141.3,165,168.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',157,2,'weight_for_age',0,30.1,33.1,53.3,56.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',157,2,'height_for_age',0,140.7,143.7,160.4,162.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',158,1,'weight_for_age',0,28.7,32.1,55.3,59.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',158,1,'height_for_age',0,137.7,141.9,165.5,169.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',158,2,'weight_for_age',0,30.3,33.4,53.5,57,300),
('DOH-JHCIS-GROWTH-2026.09.12',158,2,'height_for_age',0,141.1,144.1,160.6,163.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',159,1,'weight_for_age',0,29,32.4,55.7,59.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',159,1,'height_for_age',0,138.2,142.4,166,169.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',159,2,'weight_for_age',0,30.6,33.6,53.7,57.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',159,2,'height_for_age',0,141.5,144.4,160.8,163.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',160,1,'weight_for_age',0,29.3,32.8,56,60.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',160,1,'height_for_age',0,138.7,142.9,166.6,170.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',160,2,'weight_for_age',0,30.9,33.9,53.9,57.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',160,2,'height_for_age',0,141.8,144.7,161,163.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',161,1,'weight_for_age',0,29.6,33.1,56.3,60.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',161,1,'height_for_age',0,139.2,143.4,167.1,170.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',161,2,'weight_for_age',0,31.2,34.2,54,57.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',161,2,'height_for_age',0,142.2,145,161.2,163.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',162,1,'weight_for_age',0,29.9,33.4,56.6,60.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',162,1,'height_for_age',0,139.7,144,167.6,171.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',162,2,'weight_for_age',0,31.4,34.4,54.2,57.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',162,2,'height_for_age',0,142.5,145.3,161.4,163.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',163,1,'weight_for_age',0,30.1,33.8,57,61.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',163,1,'height_for_age',0,140.3,144.6,168,171.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',163,2,'weight_for_age',0,31.7,34.7,54.4,57.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',163,2,'height_for_age',0,142.9,145.6,161.5,164.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',164,1,'weight_for_age',0,30.4,34.1,57.4,61.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',164,1,'height_for_age',0,140.8,145.1,168.5,171.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',164,2,'weight_for_age',0,32,35,54.5,58,300),
('DOH-JHCIS-GROWTH-2026.09.12',164,2,'height_for_age',0,143.2,145.8,161.7,164.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',165,1,'weight_for_age',0,30.7,34.4,57.6,61.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',165,1,'height_for_age',0,141.4,145.7,168.9,172.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',165,2,'weight_for_age',0,32.4,35.3,54.7,58.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',165,2,'height_for_age',0,143.5,146.1,161.9,164.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',166,1,'weight_for_age',0,31,34.7,57.9,62,300),
('DOH-JHCIS-GROWTH-2026.09.12',166,1,'height_for_age',0,141.9,146.2,169.3,172.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',166,2,'weight_for_age',0,32.7,35.6,54.9,58.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',166,2,'height_for_age',0,143.8,146.4,162,164.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',167,1,'weight_for_age',0,31.4,35.1,58.3,62.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',167,1,'height_for_age',0,142.4,146.7,169.7,172.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',167,2,'weight_for_age',0,33,35.9,55,58.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',167,2,'height_for_age',0,144,146.6,162.2,164.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',168,1,'weight_for_age',0,31.8,35.5,58.7,62.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',168,1,'height_for_age',0,142.9,147.2,170,173.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',168,2,'weight_for_age',0,33.3,36.2,55.2,58.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',168,2,'height_for_age',0,144.3,146.9,162.3,164.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',169,1,'weight_for_age',0,32.2,35.9,59,62.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',169,1,'height_for_age',0,143.5,147.8,170.3,173.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',169,2,'weight_for_age',0,33.5,36.4,55.3,58.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',169,2,'height_for_age',0,144.5,147,162.4,164.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',170,1,'weight_for_age',0,32.6,36.3,59.2,63.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',170,1,'height_for_age',0,144,148.3,170.6,173.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',170,2,'weight_for_age',0,33.8,36.7,55.4,58.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',170,2,'height_for_age',0,144.6,147.2,162.5,165,300),
('DOH-JHCIS-GROWTH-2026.09.12',171,1,'weight_for_age',0,33,36.7,59.5,63.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',171,1,'height_for_age',0,144.5,148.8,170.9,173.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',171,2,'weight_for_age',0,34,36.9,55.5,58.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',171,2,'height_for_age',0,144.8,147.3,162.7,165.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',172,1,'weight_for_age',0,33.4,37.1,59.8,63.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',172,1,'height_for_age',0,145,149.3,171.2,174.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',172,2,'weight_for_age',0,34.3,37.1,55.6,59,300),
('DOH-JHCIS-GROWTH-2026.09.12',172,2,'height_for_age',0,144.9,147.4,162.8,165.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',173,1,'weight_for_age',0,33.8,37.5,60.1,63.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',173,1,'height_for_age',0,145.5,149.8,171.4,174.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',173,2,'weight_for_age',0,34.5,37.3,55.8,59.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',173,2,'height_for_age',0,145.1,147.6,162.9,165.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',174,1,'weight_for_age',0,34.2,37.9,60.4,64.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',174,1,'height_for_age',0,146.1,150.3,171.7,174.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',174,2,'weight_for_age',0,34.7,37.5,55.9,59.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',174,2,'height_for_age',0,145.2,147.7,163,165.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',175,1,'weight_for_age',0,34.5,38.2,60.6,64.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',175,1,'height_for_age',0,146.6,150.8,172,174.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',175,2,'weight_for_age',0,34.9,37.7,56,59.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',175,2,'height_for_age',0,145.3,147.8,163.1,165.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',176,1,'weight_for_age',0,34.9,38.6,60.9,64.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',176,1,'height_for_age',0,147.2,151.3,172.2,175.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',176,2,'weight_for_age',0,35.1,37.9,56.1,59.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',176,2,'height_for_age',0,145.4,147.9,163.1,165.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',177,1,'weight_for_age',0,35.3,38.9,61.1,64.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',177,1,'height_for_age',0,147.8,151.8,172.5,175.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',177,2,'weight_for_age',0,35.2,38,56.2,59.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',177,2,'height_for_age',0,145.5,148,163.2,165.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',178,1,'weight_for_age',0,35.6,39.2,61.3,65.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',178,1,'height_for_age',0,148.8,152.3,172.7,175.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',178,2,'weight_for_age',0,35.4,38.2,56.3,59.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',178,2,'height_for_age',0,145.6,148.1,163.4,165.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',179,1,'weight_for_age',0,36.1,39.6,61.6,65.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',179,1,'height_for_age',0,148.4,152.9,173,175.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',179,2,'weight_for_age',0,35.7,38.4,56.4,59.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',179,2,'height_for_age',0,145.7,148.2,163.4,165.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',180,1,'weight_for_age',0,36.5,40,61.9,65.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',180,1,'height_for_age',0,149.7,153.4,173.2,176,300),
('DOH-JHCIS-GROWTH-2026.09.12',180,2,'weight_for_age',0,35.7,38.5,56.5,59.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',180,2,'height_for_age',0,145.8,148.3,163.5,166,300),
('DOH-JHCIS-GROWTH-2026.09.12',181,1,'weight_for_age',0,36.9,40.4,62.1,65.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',181,1,'height_for_age',0,150.3,153.9,173.5,176.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',181,2,'weight_for_age',0,36,38.7,56.6,59.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',181,2,'height_for_age',0,145.8,148.3,163.6,166.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',182,1,'weight_for_age',0,37.3,40.7,62.3,66,300),
('DOH-JHCIS-GROWTH-2026.09.12',182,1,'height_for_age',0,150.9,154.4,173.7,176.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',182,2,'weight_for_age',0,36.2,38.8,56.7,59.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',182,2,'height_for_age',0,145.9,148.4,163.7,166.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',183,1,'weight_for_age',0,37.6,41,62.5,66.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',183,1,'height_for_age',0,151.5,154.9,174,176.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',183,2,'weight_for_age',0,36.3,38.9,56.8,60,300),
('DOH-JHCIS-GROWTH-2026.09.12',183,2,'height_for_age',0,146,148.5,163.7,166.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',184,1,'weight_for_age',0,38,41.4,62.6,66.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',184,1,'height_for_age',0,152,155.4,174.2,177,300),
('DOH-JHCIS-GROWTH-2026.09.12',184,2,'weight_for_age',0,36.4,39,56.8,60,300),
('DOH-JHCIS-GROWTH-2026.09.12',184,2,'height_for_age',0,146.1,148.6,163.7,166.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',185,1,'weight_for_age',0,38.3,41.7,62.9,66.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',185,1,'height_for_age',0,152.5,155.8,174.4,177.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',185,2,'weight_for_age',0,36.6,39.2,56.9,60.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',185,2,'height_for_age',0,146.1,148.6,163.8,166.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',186,1,'weight_for_age',0,38.7,42.1,63.1,66.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',186,1,'height_for_age',0,153,156.3,174.7,177.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',186,2,'weight_for_age',0,36.7,39.3,56.9,60.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',186,2,'height_for_age',0,146.2,148.7,163.8,166.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',187,1,'weight_for_age',0,39,42.4,63.3,66.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',187,1,'height_for_age',0,153.4,156.7,174.9,177.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',187,2,'weight_for_age',0,36.9,39.5,57,60.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',187,2,'height_for_age',0,146.2,148.7,163.9,166.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',188,1,'weight_for_age',0,39.3,42.7,63.4,66.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',188,1,'height_for_age',0,153.8,157,175.1,177.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',188,2,'weight_for_age',0,37,39.6,57,60.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',188,2,'height_for_age',0,146.3,148.8,163.9,166.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',189,1,'weight_for_age',0,39.6,43,63.6,67.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',189,1,'height_for_age',0,154.2,157.3,175.3,178.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',189,2,'weight_for_age',0,37.1,39.7,57.1,60.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',189,2,'height_for_age',0,146.3,148.8,164,166.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',190,1,'weight_for_age',0,39.9,43.2,63.8,67.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',190,1,'height_for_age',0,154.5,157.7,175.5,178.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',190,2,'weight_for_age',0,37.2,39.8,57.1,60.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',190,2,'height_for_age',0,146.4,148.9,164,166.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',191,1,'weight_for_age',0,40.2,43.5,63.9,67.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',191,1,'height_for_age',0,154.9,157.9,175.7,178.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',191,2,'weight_for_age',0,37.3,39.9,57.2,60.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',191,2,'height_for_age',0,146.4,148.9,164,166.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',192,1,'weight_for_age',0,40.4,43.7,64.2,67.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',192,1,'height_for_age',0,155.1,158.2,175.9,178.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',192,2,'weight_for_age',0,37.4,40,57.2,60.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',192,2,'height_for_age',0,146.5,149,164,166.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',193,1,'weight_for_age',0,40.7,44,64.3,67.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',193,1,'height_for_age',0,155.4,158.5,176,178.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',193,2,'weight_for_age',0,37.5,40.1,57.2,60.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',193,2,'height_for_age',0,146.5,149,164,166.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',194,1,'weight_for_age',0,40.9,44.2,64.5,67.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',194,1,'height_for_age',0,155.6,158.7,176.1,178.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',194,2,'weight_for_age',0,37.6,40.2,57.3,60.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',194,2,'height_for_age',0,146.5,149,164,166.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',195,1,'weight_for_age',0,41.1,44.4,64.6,68,300),
('DOH-JHCIS-GROWTH-2026.09.12',195,1,'height_for_age',0,155.9,158.9,176.3,179,300),
('DOH-JHCIS-GROWTH-2026.09.12',195,2,'weight_for_age',0,37.7,40.2,57.3,60.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',195,2,'height_for_age',0,146.6,149.1,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',196,1,'weight_for_age',0,41.3,44.6,64.7,68.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',196,1,'height_for_age',0,156.1,159.1,176.4,179.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',196,2,'weight_for_age',0,37.8,40.3,57.4,60.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',196,2,'height_for_age',0,146.6,149.1,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',197,1,'weight_for_age',0,41.5,44.8,64.9,68.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',197,1,'height_for_age',0,156.3,159.3,176.5,179.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',197,2,'weight_for_age',0,37.9,40.4,57.4,60.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',197,2,'height_for_age',0,146.6,149.1,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',198,1,'weight_for_age',0,41.7,45,65,68.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',198,1,'height_for_age',0,156.4,159.5,176.6,179.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',198,2,'weight_for_age',0,37.9,40.4,57.5,60.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',198,2,'height_for_age',0,146.7,149.2,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',199,1,'weight_for_age',0,41.9,45.2,65.2,68.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',199,1,'height_for_age',0,156.6,159.6,176.7,179.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',199,2,'weight_for_age',0,38,40.5,57.5,60.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',199,2,'height_for_age',0,146.7,149.2,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',200,1,'weight_for_age',0,42.1,45.4,65.3,68.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',200,1,'height_for_age',0,156.8,159.8,176.8,179.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',200,2,'weight_for_age',0,38,40.5,57.5,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',200,2,'height_for_age',0,146.7,149.2,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',201,1,'weight_for_age',0,42.3,45.6,65.4,68.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',201,1,'height_for_age',0,156.9,159.9,176.9,179.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',201,2,'weight_for_age',0,38.1,40.6,57.6,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',201,2,'height_for_age',0,146.8,149.3,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',202,1,'weight_for_age',0,42.5,45.8,65.5,68.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',202,1,'height_for_age',0,157.1,160,177,179.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',202,2,'weight_for_age',0,38.1,40.6,57.6,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',202,2,'height_for_age',0,146.8,149.3,164.1,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',203,1,'weight_for_age',0,42.7,46,65.6,68.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',203,1,'height_for_age',0,157.2,160.2,177.1,179.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',203,2,'weight_for_age',0,38.2,40.7,57.6,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',203,2,'height_for_age',0,146.9,149.4,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',204,1,'weight_for_age',0,42.9,46.2,65.8,69,300),
('DOH-JHCIS-GROWTH-2026.09.12',204,1,'height_for_age',0,157.3,160.3,177.2,179.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',204,2,'weight_for_age',0,38.2,40.7,57.6,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',204,2,'height_for_age',0,146.9,149.4,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',205,1,'weight_for_age',0,43,46.3,65.9,69.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',205,1,'height_for_age',0,157.5,160.4,177.2,179.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',205,2,'weight_for_age',0,38.3,40.8,57.6,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',205,2,'height_for_age',0,147,149.5,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',206,1,'weight_for_age',0,43.2,46.5,66,69.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',206,1,'height_for_age',0,157.6,160.5,177.3,179.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',206,2,'weight_for_age',0,38.3,40.8,57.6,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',206,2,'height_for_age',0,147,149.5,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',207,1,'weight_for_age',0,43.4,46.7,66.1,69.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',207,1,'height_for_age',0,157.7,160.6,177.3,180,300),
('DOH-JHCIS-GROWTH-2026.09.12',207,2,'weight_for_age',0,38.3,40.8,57.6,60.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',207,2,'height_for_age',0,147.1,149.5,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',208,1,'weight_for_age',0,43.6,46.9,66.2,69.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',208,1,'height_for_age',0,157.8,160.7,177.4,180,300),
('DOH-JHCIS-GROWTH-2026.09.12',208,2,'weight_for_age',0,38.4,40.9,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',208,2,'height_for_age',0,147.1,149.5,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',209,1,'weight_for_age',0,43.7,47,66.3,69.5,300),
('DOH-JHCIS-GROWTH-2026.09.12',209,1,'height_for_age',0,158,160.8,177.4,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',209,2,'weight_for_age',0,38.4,40.9,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',209,2,'height_for_age',0,147.2,149.6,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',210,1,'weight_for_age',0,43.9,47.1,66.4,69.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',210,1,'height_for_age',0,158.1,160.9,177.4,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',210,2,'weight_for_age',0,38.5,41,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',210,2,'height_for_age',0,147.2,149.6,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',211,1,'weight_for_age',0,44.1,47.3,66.4,69.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',211,1,'height_for_age',0,158.2,161,177.4,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',211,2,'weight_for_age',0,38.5,41,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',211,2,'height_for_age',0,147.2,149.6,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',212,1,'weight_for_age',0,44.2,47.4,66.5,69.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',212,1,'height_for_age',0,158.3,161,177.4,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',212,2,'weight_for_age',0,38.6,41.1,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',212,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',213,1,'weight_for_age',0,44.4,47.6,66.6,69.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',213,1,'height_for_age',0,158.4,161.1,177.4,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',213,2,'weight_for_age',0,38.6,41.1,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',213,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',214,1,'weight_for_age',0,44.5,47.7,66.7,69.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',214,1,'height_for_age',0,158.5,161.2,177.5,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',214,2,'weight_for_age',0,38.6,41.1,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',214,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',215,1,'weight_for_age',0,44.7,47.9,66.8,69.8,300),
('DOH-JHCIS-GROWTH-2026.09.12',215,1,'height_for_age',0,158.5,161.2,177.5,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',215,2,'weight_for_age',0,38.7,41.2,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',215,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',216,1,'weight_for_age',0,44.8,48,66.9,69.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',216,1,'height_for_age',0,158.6,161.3,177.5,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',216,2,'weight_for_age',0,38.7,41.2,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',216,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',217,1,'weight_for_age',0,44.9,48.1,66.9,69.9,300),
('DOH-JHCIS-GROWTH-2026.09.12',217,1,'height_for_age',0,158.7,161.3,177.5,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',217,2,'weight_for_age',0,38.8,41.3,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',217,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',218,1,'weight_for_age',0,45.2,48.3,67,70,300),
('DOH-JHCIS-GROWTH-2026.09.12',218,1,'height_for_age',0,158.7,161.4,177.5,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',218,2,'weight_for_age',0,38.8,41.3,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',218,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',219,1,'weight_for_age',0,45.3,48.4,67,70,300),
('DOH-JHCIS-GROWTH-2026.09.12',219,1,'height_for_age',0,158.8,161.4,177.5,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',219,2,'weight_for_age',0,38.9,41.4,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',219,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',220,1,'weight_for_age',0,45.4,48.5,67.1,70.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',220,1,'height_for_age',0,158.8,161.5,177.5,180.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',220,2,'weight_for_age',0,38.9,41.4,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',220,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',221,1,'weight_for_age',0,45.4,48.5,67.1,70.1,300),
('DOH-JHCIS-GROWTH-2026.09.12',221,1,'height_for_age',0,158.9,161.5,177.6,180.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',221,2,'weight_for_age',0,38.9,41.4,57.7,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',221,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',222,1,'weight_for_age',0,45.5,48.6,67.2,70.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',222,1,'height_for_age',0,158.9,161.5,177.6,180.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',222,2,'weight_for_age',0,39,41.5,57.8,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',222,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',223,1,'weight_for_age',0,45.6,48.7,67.2,70.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',223,1,'height_for_age',0,158.9,161.5,177.6,180.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',223,2,'weight_for_age',0,39,41.5,57.8,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',223,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',224,1,'weight_for_age',0,45.7,48.7,67.3,70.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',224,1,'height_for_age',0,158.9,161.6,177.6,180.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',224,2,'weight_for_age',0,39,41.5,57.8,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',224,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',225,1,'weight_for_age',0,45.7,48.8,67.3,70.3,300),
('DOH-JHCIS-GROWTH-2026.09.12',225,1,'height_for_age',0,159,161.6,177.6,180.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',225,2,'weight_for_age',0,39,41.5,57.8,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',225,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',226,1,'weight_for_age',0,45.8,48.8,67.4,70.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',226,1,'height_for_age',0,159,161.6,177.6,180.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',226,2,'weight_for_age',0,39.1,41.6,57.8,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',226,2,'height_for_age',0,147.3,149.7,164.2,166.6,300),
('DOH-JHCIS-GROWTH-2026.09.12',227,1,'weight_for_age',0,45.8,48.8,67.4,70.4,300),
('DOH-JHCIS-GROWTH-2026.09.12',227,1,'height_for_age',0,159,161.6,177.6,180.2,300),
('DOH-JHCIS-GROWTH-2026.09.12',227,2,'weight_for_age',0,39.1,41.6,57.8,60.7,300),
('DOH-JHCIS-GROWTH-2026.09.12',227,2,'height_for_age',0,147.3,149.7,164.2,166.6,300);

create table if not exists private.growth_wh_reference_v204 (
  reference_version text not null,
  age_low_years integer not null,
  age_max_years integer not null,
  sex smallint not null check(sex in (1,2)),
  height_cm numeric(6,2) not null,
  min_weight numeric(8,2) not null,
  level1_high numeric(8,2) not null,
  level2_high numeric(8,2) not null,
  level3_high numeric(8,2) not null,
  level4_high numeric(8,2) not null,
  level5_high numeric(8,2) not null,
  max_weight numeric(8,2) not null,
  primary key(reference_version,age_low_years,age_max_years,sex,height_cm)
);

revoke all on private.growth_wh_reference_v204 from public,anon,authenticated;

delete from private.growth_wh_reference_v204 where reference_version='DOH-JHCIS-GROWTH-2026.09.12';

insert into private.growth_wh_reference_v204
(reference_version,age_low_years,age_max_years,sex,height_cm,min_weight,level1_high,level2_high,level3_high,level4_high,level5_high,max_weight) values
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,45,1.5,1.9,2,2.8,3,3.3,3.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,45.5,1.6,2,2.1,2.9,3.1,3.4,4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,46,1.7,2.1,2.2,3,3.1,3.5,4.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,46.5,1.7,2.2,2.3,3.1,3.2,3.6,4.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,47,1.8,2.2,2.3,3.2,3.3,3.7,4.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,47.5,1.8,2.3,2.4,3.3,3.4,3.8,4.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,48,1.9,2.4,2.5,3.4,3.6,3.9,4.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,48.5,1.9,2.5,2.6,3.5,3.7,4,4.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,49,2,2.5,2.6,3.6,3.8,4.2,4.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,49.5,2.1,2.6,2.7,3.7,3.9,4.3,5.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,50,2.1,2.7,2.8,3.8,4,4.4,5.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,50.5,2.2,2.8,2.9,3.9,4.1,4.5,5.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,51,2.3,2.9,3,4.1,4.2,4.7,5.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,51.5,2.4,3,3.1,4.2,4.4,4.8,5.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,52,2.4,3.1,3.2,4.3,4.5,5,5.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,52.5,2.5,3.2,3.3,4.4,4.6,5.1,6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,53,2.6,3.3,3.4,4.6,4.8,5.3,6.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,53.5,2.7,3.4,3.5,4.7,4.9,5.4,6.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,54,2.8,3.5,3.7,4.9,5.1,5.6,6.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,54.5,2.9,3.6,3.8,5,5.3,5.8,6.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,55,3,3.7,3.9,5.2,5.4,6,7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,55.5,3.1,3.9,4,5.3,5.6,6.1,7.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,56,3.2,4,4.2,5.5,5.8,6.3,7.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,56.5,3.3,4.1,4.3,5.7,5.9,6.5,7.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,57,3.4,4.2,4.4,5.8,6.1,6.7,7.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,57.5,3.5,4.4,4.6,6,6.3,6.9,8.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,58,3.6,4.5,4.7,6.2,6.4,7.1,8.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,58.5,3.7,4.6,4.8,6.3,6.6,7.2,8.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,59,3.8,4.7,4.9,6.5,6.8,7.4,8.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,59.5,3.9,4.9,5.1,6.7,7,7.6,8.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,60,4,5,5.2,6.8,7.1,7.8,9.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,60.5,4,5.1,5.3,7,7.3,8,9.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,61,4.1,5.2,5.4,7.1,7.4,8.1,9.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,61.5,4.2,5.3,5.6,7.3,7.6,8.3,9.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,62,4.3,5.5,5.7,7.4,7.7,8.5,9.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,62.5,4.4,5.6,5.8,7.6,7.9,8.6,10.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,63,4.5,5.7,5.9,7.7,8,8.8,10.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,63.5,4.6,5.8,6,7.8,8.2,8.9,10.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,64,4.7,5.9,6.1,8,8.3,9.1,10.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,64.5,4.7,6,6.2,8.1,8.5,9.3,10.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,65,4.8,6.1,6.3,8.2,8.6,9.4,11),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,65.5,4.9,6.2,6.4,8.4,8.7,9.6,11.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,66,5,6.3,6.6,8.5,8.9,9.7,11.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,66.5,5.1,6.4,6.7,8.6,9,9.9,11.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,67,5.1,6.5,6.8,8.8,9.2,10,11.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,67.5,5.2,6.6,6.9,8.9,9.3,10.2,11.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,68,5.3,6.7,7,9,9.4,10.3,12.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,68.5,5.4,6.8,7.1,9.2,9.6,10.5,12.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,69,5.4,6.9,7.2,9.3,9.7,10.6,12.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,69.5,5.5,7,7.3,9.4,9.8,10.8,12.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,70,5.6,7.1,7.4,9.6,10,10.9,12.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,70.5,5.7,7.2,7.5,9.7,10.1,11.1,12.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,71,5.7,7.3,7.6,9.8,10.2,11.2,13.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,71.5,5.8,7.4,7.7,9.9,10.4,11.3,13.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,72,5.9,7.5,7.8,10.1,10.5,11.5,13.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,72.5,5.9,7.5,7.9,10.2,10.6,11.6,13.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,73,6,7.6,7.9,10.3,10.8,11.8,13.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,73.5,6.1,7.7,8,10.4,10.9,11.9,14),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,74,6.2,7.8,8.1,10.6,11,12.1,14.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,74.5,6.2,7.9,8.2,10.7,11.2,12.2,14.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,75,6.3,8,8.3,10.8,11.3,12.3,14.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,75.5,6.3,8.1,8.4,10.9,11.4,12.5,14.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,76,6.4,8.2,8.5,11,11.5,12.6,14.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,76.5,6.5,8.2,8.6,11.1,11.6,12.7,14.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,77,6.5,8.3,8.7,11.2,11.7,12.8,15.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,77.5,6.6,8.4,8.7,11.4,11.9,13,15.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,78,6.7,8.5,8.8,11.5,12,13.1,15.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,78.5,6.7,8.6,8.9,11.6,12.1,13.2,15.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,79,6.8,8.6,9,11.7,12.2,13.3,15.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,79.5,6.8,8.7,9.1,11.8,12.3,13.4,15.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,80,6.9,8.8,9.1,11.9,12.4,13.6,15.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,80.5,7,8.9,9.2,12,12.5,13.7,16),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,81,7,9,9.3,12.1,12.6,13.8,16.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,81.5,7.1,9,9.4,12.2,12.7,13.9,16.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,82,7.2,9.1,9.5,12.3,12.8,14,16.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,82.5,7.2,9.2,9.6,12.4,13,14.2,16.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,83,7.3,9.3,9.7,12.5,13.1,14.3,16.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,83.5,7.4,9.4,9.8,12.7,13.2,14.4,16.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,84,7.5,9.5,9.9,12.8,13.3,14.6,17.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,84.5,7.6,9.6,10,12.9,13.5,14.7,17.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,85,7.6,9.7,10.1,13,13.6,14.9,17.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,85.5,7.7,9.8,10.2,13.2,13.8,15,17.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,86,7.8,9.9,10.3,13.3,13.9,15.2,17.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,86.5,7.9,10,10.4,13.4,14,15.3,17.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,87,8,10.1,10.5,13.6,14.2,15.5,18.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,87.5,8.1,10.3,10.7,13.7,14.3,15.6,18.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,88,8.2,10.4,10.8,13.9,14.5,15.8,18.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,88.5,8.3,10.5,10.9,14,14.6,15.9,18.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,89,8.3,10.6,11,14.1,14.7,16.1,18.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,89.5,8.4,10.7,11.1,14.3,14.9,16.2,18.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,90,8.5,10.8,11.2,14.4,15,16.4,19.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,90.5,8.6,10.9,11.3,14.5,15.1,16.5,19.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,91,8.7,11,11.4,14.7,15.3,16.7,19.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,91.5,8.8,11.1,11.5,14.8,15.4,16.8,19.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,92,8.8,11.2,11.6,14.9,15.6,17,19.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,92.5,8.9,11.3,11.7,15,15.7,17.1,19.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,93,9,11.4,11.8,15.2,15.8,17.3,20.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,93.5,9.1,11.5,11.9,15.3,16,17.4,20.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,94,9.1,11.6,12,15.4,16.1,17.6,20.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,94.5,9.2,11.7,12.1,15.6,16.3,17.7,20.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,95,9.3,11.8,12.2,15.7,16.4,17.9,20.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,95.5,9.4,11.9,12.3,15.9,16.5,18,21),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,96,9.5,12,12.5,16,16.7,18.2,21.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,96.5,9.5,12.1,12.6,16.1,16.8,18.4,21.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,97,9.6,12.2,12.7,16.3,17,18.5,21.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,97.5,9.7,12.3,12.8,16.4,17.1,18.7,21.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,98,9.8,12.4,12.9,16.6,17.3,18.9,22),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,98.5,9.8,12.5,13,16.7,17.5,19.1,22.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,99,9.9,12.6,13.1,16.9,17.6,19.2,22.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,99.5,10,12.7,13.2,17,17.8,19.4,22.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,100,10.1,12.8,13.3,17.2,18,19.6,22.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,100.5,10.2,12.9,13.5,17.4,18.1,19.8,23.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,101,10.2,13.1,13.6,17.5,18.3,20,23.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,101.5,10.3,13.2,13.7,17.7,18.5,20.2,23.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,102,10.4,13.3,13.8,17.9,18.7,20.4,23.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,102.5,10.5,13.4,13.9,18,18.8,20.6,24.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,103,10.6,13.5,14.1,18.2,19,20.8,24.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,103.5,10.7,13.6,14.2,18.4,19.2,21,24.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,104,10.7,13.8,14.3,18.6,19.4,21.2,24.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,104.5,10.8,13.9,14.5,18.7,19.6,21.5,25.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,105,10.9,14,14.6,18.9,19.8,21.7,25.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,105.5,11,14.1,14.7,19.1,20,21.9,25.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,106,11.1,14.3,14.9,19.3,20.2,22.1,26),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,106.5,11.2,14.4,15,19.5,20.4,22.4,26.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,107,11.3,14.5,15.1,19.7,20.6,22.6,26.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,107.5,11.3,14.6,15.3,19.9,20.8,22.8,26.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,108,11.4,14.8,15.4,20.1,21,23.1,27.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,108.5,11.5,14.9,15.5,20.3,21.2,23.3,27.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,109,11.6,15,15.7,20.5,21.4,23.6,27.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,109.5,11.7,15.2,15.8,20.7,21.7,23.8,28.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,1,110,11.8,15.3,16,20.9,21.9,24.1,28.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,45,1.6,2,2.1,2.8,3,3.3,3.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,45.5,1.6,2,2.1,2.9,3.1,3.4,4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,46,1.7,2.1,2.2,3,3.2,3.5,4.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,46.5,1.7,2.2,2.3,3.1,3.3,3.6,4.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,47,1.8,2.3,2.4,3.2,3.4,3.7,4.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,47.5,1.8,2.3,2.4,3.3,3.5,3.8,4.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,48,1.9,2.4,2.5,3.4,3.6,4,4.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,48.5,2,2.5,2.6,3.5,3.7,4.1,4.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,49,2,2.5,2.7,3.6,3.8,4.2,5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,49.5,2.1,2.6,2.7,3.7,3.9,4.3,5.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,50,2.1,2.7,2.8,3.9,4,4.5,5.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,50.5,2.2,2.8,2.9,4,4.2,4.6,5.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,51,2.3,2.9,3,4.1,4.3,4.8,5.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,51.5,2.3,3,3.1,4.2,4.4,4.9,5.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,52,2.4,3.1,3.2,4.4,4.6,5.1,6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,52.5,2.5,3.2,3.3,4.5,4.7,5.2,6.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,53,2.6,3.3,3.4,4.6,4.9,5.4,6.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,53.5,2.6,3.4,3.5,4.8,5,5.5,6.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,54,2.7,3.5,3.7,4.9,5.2,5.7,6.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,54.5,2.8,3.6,3.8,5.1,5.3,5.9,7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,55,2.9,3.7,3.9,5.2,5.5,6.1,7.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,55.5,3,3.8,4,5.4,5.7,6.3,7.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,56,3.1,3.9,4.1,5.5,5.8,6.4,7.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,56.5,3.1,4,4.2,5.7,6,6.6,7.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,57,3.2,4.2,4.3,5.9,6.1,6.8,8.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,57.5,3.3,4.3,4.5,6,6.3,7,8.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,58,3.4,4.4,4.6,6.2,6.5,7.1,8.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,58.5,3.5,4.5,4.7,6.3,6.6,7.3,8.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,59,3.6,4.6,4.8,6.5,6.8,7.5,8.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,59.5,3.7,4.7,4.9,6.6,6.9,7.7,9.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,60,3.7,4.8,5,6.8,7.1,7.8,9.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,60.5,3.8,4.9,5.2,6.9,7.3,8,9.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,61,3.9,5,5.3,7.1,7.4,8.2,9.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,61.5,4,5.1,5.4,7.2,7.6,8.4,9.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,62,4.1,5.2,5.5,7.3,7.7,8.5,10.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,62.5,4.1,5.3,5.6,7.5,7.8,8.7,10.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,63,4.2,5.4,5.7,7.6,8,8.8,10.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,63.5,4.3,5.5,5.8,7.8,8.1,9,10.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,64,4.4,5.6,5.9,7.9,8.3,9.1,10.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,64.5,4.4,5.7,6,8,8.4,9.3,11.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,65,4.5,5.8,6.1,8.1,8.6,9.5,11.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,65.5,4.6,5.9,6.2,8.3,8.7,9.6,11.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,66,4.6,6,6.3,8.4,8.8,9.8,11.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,66.5,4.7,6.1,6.4,8.5,9,9.9,11.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,67,4.8,6.2,6.5,8.7,9.1,10,12),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,67.5,4.9,6.3,6.6,8.8,9.2,10.2,12.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,68,4.9,6.4,6.7,8.9,9.4,10.3,12.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,68.5,5,6.5,6.8,9,9.5,10.5,12.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,69,5.1,6.6,6.9,9.2,9.6,10.6,12.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,69.5,5.1,6.7,7,9.3,9.7,10.7,12.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,70,5.2,6.8,7,9.4,9.9,10.9,12.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,70.5,5.3,6.8,7.1,9.5,10,11,13.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,71,5.3,6.9,7.2,9.6,10.1,11.1,13.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,71.5,5.4,7,7.3,9.7,10.2,11.3,13.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,72,5.5,7.1,7.4,9.8,10.3,11.4,13.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,72.5,5.5,7.2,7.5,10,10.5,11.5,13.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,73,5.6,7.3,7.6,10.1,10.6,11.7,13.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,73.5,5.7,7.3,7.7,10.2,10.7,11.8,14),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,74,5.7,7.4,7.8,10.3,10.8,11.9,14.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,74.5,5.8,7.5,7.8,10.4,10.9,12,14.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,75,5.9,7.6,7.9,10.5,11,12.2,14.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,75.5,5.9,7.7,8,10.6,11.1,12.3,14.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,76,6,7.7,8.1,10.7,11.2,12.4,14.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,76.5,6,7.8,8.2,10.8,11.4,12.5,14.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,77,6.1,7.9,8.2,10.9,11.5,12.6,15),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,77.5,6.2,8,8.3,11,11.6,12.8,15.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,78,6.2,8.1,8.4,11.1,11.7,12.9,15.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,78.5,6.3,8.1,8.5,11.2,11.8,13,15.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,79,6.3,8.2,8.6,11.4,11.9,13.1,15.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,79.5,6.4,8.3,8.7,11.5,12,13.3,15.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,80,6.5,8.4,8.8,11.6,12.1,13.4,15.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,80.5,6.5,8.5,8.8,11.7,12.3,13.5,16),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,81,6.6,8.6,8.9,11.8,12.4,13.7,16.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,81.5,6.7,8.7,9,11.9,12.5,13.8,16.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,82,6.8,8.7,9.1,12.1,12.6,13.9,16.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,82.5,6.8,8.8,9.2,12.2,12.8,14.1,16.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,83,6.9,8.9,9.3,12.3,12.9,14.2,16.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,83.5,7,9,9.4,12.5,13.1,14.4,17.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,84,7.1,9.1,9.5,12.6,13.2,14.5,17.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,84.5,7.1,9.2,9.6,12.7,13.3,14.7,17.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,85,7.2,9.3,9.8,12.9,13.5,14.9,17.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,85.5,7.3,9.4,9.9,13,13.6,15,17.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,86,7.4,9.6,10,13.2,13.8,15.2,18),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,86.5,7.5,9.7,10.1,13.3,13.9,15.4,18.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,87,7.5,9.8,10.2,13.4,14.1,15.5,18.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,87.5,7.6,9.9,10.3,13.6,14.2,15.7,18.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,88,7.7,10,10.4,13.7,14.4,15.9,18.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,88.5,7.8,10.1,10.5,13.9,14.5,16,19),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,89,7.9,10.2,10.6,14,14.7,16.2,19.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,89.5,7.9,10.3,10.7,14.2,14.8,16.4,19.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,90,8,10.4,10.8,14.3,15,16.5,19.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,90.5,8.1,10.5,11,14.4,15.1,16.7,19.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,91,8.2,10.6,11.1,14.6,15.3,16.9,20),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,91.5,8.3,10.7,11.2,14.7,15.5,17,20.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,92,8.3,10.8,11.3,14.9,15.6,17.2,20.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,92.5,8.4,10.9,11.4,15,15.8,17.4,20.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,93,8.5,11,11.5,15.2,15.9,17.5,20.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,93.5,8.6,11.1,11.6,15.3,16.1,17.7,21),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,94,8.6,11.2,11.7,15.5,16.2,17.9,21.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,94.5,8.7,11.3,11.8,15.6,16.4,18,21.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,95,8.8,11.4,11.9,15.7,16.5,18.2,21.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,95.5,8.9,11.5,12,15.9,16.7,18.4,21.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,96,8.9,11.6,12.1,16,16.8,18.6,22),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,96.5,9,11.7,12.3,16.2,17,18.7,22.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,97,9.1,11.9,12.4,16.3,17.1,18.9,22.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,97.5,9.2,12,12.5,16.5,17.3,19.1,22.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,98,9.3,12.1,12.6,16.6,17.5,19.3,22.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,98.5,9.3,12.2,12.7,16.8,17.6,19.5,23.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,99,9.4,12.3,12.8,17,17.8,19.6,23.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,99.5,9.5,12.4,12.9,17.1,18,19.8,23.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,100,9.6,12.5,13.1,17.3,18.1,20,23.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,100.5,9.7,12.6,13.2,17.4,18.3,20.2,24.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,101,9.7,12.7,13.3,17.6,18.5,20.4,24.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,101.5,9.8,12.9,13.4,17.8,18.7,20.6,24.5),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,102,9.9,13,13.6,18,18.9,20.8,24.8),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,102.5,10,13.1,13.7,18.1,19,21,25.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,103,10.1,13.2,13.8,18.3,19.2,21.3,25.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,103.5,10.2,13.4,13.9,18.5,19.4,21.5,25.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,104,10.3,13.5,14.1,18.7,19.6,21.7,25.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,104.5,10.4,13.6,14.2,18.9,19.8,21.9,26.1),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,105,10.5,13.7,14.4,19.1,20,22.2,26.4),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,105.5,10.6,13.9,14.5,19.3,20.2,22.4,26.7),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,106,10.7,14,14.6,19.5,20.5,22.6,27),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,106.5,10.8,14.2,14.8,19.7,20.7,22.9,27.3),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,107,10.9,14.3,14.9,19.9,20.9,23.1,27.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,107.5,11,14.4,15.1,20.1,21.1,23.4,27.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,108,11.1,14.6,15.2,20.3,21.3,23.6,28.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,108.5,11.2,14.7,15.4,20.5,21.6,23.9,28.6),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,109,11.3,14.9,15.6,20.7,21.8,24.2,28.9),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,109.5,11.4,15,15.7,21,22,24.4,29.2),
('DOH-JHCIS-GROWTH-2026.09.12',0,1,2,110,11.5,15.2,15.9,21.2,22.3,24.7,29.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,65,4.9,6.2,6.5,8.4,8.8,9.6,11.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,65.5,5,6.3,6.6,8.6,8.9,9.8,11.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,66,5.1,6.4,6.7,8.7,9.1,9.9,11.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,66.5,5.2,6.5,6.8,8.8,9.2,10.1,11.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,67,5.2,6.6,6.9,9,9.4,10.2,12),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,67.5,5.3,6.7,7,9.1,9.5,10.4,12.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,68,5.4,6.8,7.1,9.2,9.6,10.5,12.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,68.5,5.5,6.9,7.2,9.3,9.8,10.7,12.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,69,5.5,7,7.3,9.5,9.9,10.8,12.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,69.5,5.6,7.1,7.4,9.6,10,11,12.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,70,5.7,7.2,7.5,9.7,10.2,11.1,13),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,70.5,5.8,7.3,7.6,9.9,10.3,11.3,13.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,71,5.8,7.4,7.7,10,10.4,11.4,13.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,71.5,5.9,7.5,7.8,10.1,10.6,11.6,13.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,72,6,7.6,7.9,10.2,10.7,11.7,13.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,72.5,6,7.7,8,10.4,10.8,11.8,13.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,73,6.1,7.8,8.1,10.5,11,12,14),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,73.5,6.2,7.8,8.2,10.6,11.1,12.1,14.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,74,6.2,7.9,8.3,10.7,11.2,12.2,14.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,74.5,6.3,8,8.3,10.8,11.3,12.4,14.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,75,6.4,8.1,8.4,11,11.4,12.5,14.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,75.5,6.4,8.2,8.5,11.1,11.6,12.6,14.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,76,6.5,8.3,8.6,11.2,11.7,12.8,15),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,76.5,6.6,8.4,8.7,11.3,11.8,12.9,15.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,77,6.6,8.4,8.8,11.4,11.9,13,15.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,77.5,6.7,8.5,8.9,11.5,12,13.1,15.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,78,6.7,8.6,8.9,11.6,12.1,13.3,15.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,78.5,6.8,8.7,9,11.7,12.2,13.4,15.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,79,6.9,8.7,9.1,11.8,12.3,13.5,15.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,79.5,6.9,8.8,9.2,11.9,12.4,13.6,15.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,80,7,8.9,9.3,12,12.6,13.7,16.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,80.5,7.1,9,9.4,12.1,12.7,13.8,16.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,81,7.1,9.1,9.4,12.2,12.8,14,16.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,81.5,7.2,9.2,9.5,12.3,12.9,14.1,16.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,82,7.3,9.3,9.6,12.5,13,14.2,16.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,82.5,7.4,9.3,9.7,12.6,13.1,14.4,16.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,83,7.4,9.4,9.8,12.7,13.3,14.5,17),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,83.5,7.5,9.5,9.9,12.8,13.4,14.6,17.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,84,7.6,9.6,10,13,13.5,14.8,17.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,84.5,7.7,9.8,10.1,13.1,13.7,14.9,17.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,85,7.8,9.9,10.3,13.2,13.8,15.1,17.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,85.5,7.9,10,10.4,13.4,13.9,15.2,17.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,86,7.9,10.1,10.5,13.5,14.1,15.4,17.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,86.5,8,10.2,10.6,13.6,14.2,15.5,18.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,87,8.1,10.3,10.7,13.8,14.4,15.7,18.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,87.5,8.2,10.4,10.8,13.9,14.5,15.8,18.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,88,8.3,10.5,10.9,14,14.7,16,18.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,88.5,8.4,10.6,11,14.2,14.8,16.1,18.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,89,8.5,10.7,11.1,14.3,14.9,16.3,19),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,89.5,8.6,10.8,11.2,14.4,15.1,16.4,19.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,90,8.6,10.9,11.4,14.6,15.2,16.6,19.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,90.5,8.7,11,11.5,14.7,15.3,16.7,19.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,91,8.8,11.1,11.6,14.8,15.5,16.9,19.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,91.5,8.9,11.2,11.7,15,15.6,17,19.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,92,8.9,11.3,11.8,15.1,15.8,17.2,20),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,92.5,9,11.4,11.9,15.2,15.9,17.3,20.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,93,9.1,11.5,12,15.4,16,17.5,20.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,93.5,9.2,11.6,12.1,15.5,16.2,17.6,20.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,94,9.3,11.7,12.2,15.6,16.3,17.8,20.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,94.5,9.3,11.8,12.3,15.8,16.5,17.9,20.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,95,9.4,11.9,12.4,15.9,16.6,18.1,21.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,95.5,9.5,12,12.5,16,16.7,18.3,21.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,96,9.6,12.1,12.6,16.2,16.9,18.4,21.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,96.5,9.6,12.2,12.7,16.3,17,18.6,21.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,97,9.7,12.3,12.8,16.5,17.2,18.8,21.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,97.5,9.8,12.4,12.9,16.6,17.4,18.9,22.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,98,9.9,12.5,13,16.8,17.5,19.1,22.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,98.5,9.9,12.7,13.2,16.9,17.7,19.3,22.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,99,10,12.8,13.3,17.1,17.9,19.5,22.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,99.5,10.1,12.9,13.4,17.3,18,19.7,23),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,100,10.2,13,13.5,17.4,18.2,19.9,23.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,100.5,10.3,13.1,13.6,17.6,18.4,20.1,23.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,101,10.4,13.2,13.8,17.8,18.5,20.3,23.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,101.5,10.4,13.3,13.9,17.9,18.7,20.5,24),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,102,10.5,13.5,14,18.1,18.9,20.7,24.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,102.5,10.6,13.6,14.1,18.3,19.1,20.9,24.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,103,10.7,13.7,14.3,18.5,19.3,21.1,24.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,103.5,10.8,13.8,14.4,18.6,19.5,21.3,25),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,104,10.9,13.9,14.5,18.8,19.7,21.6,25.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,104.5,10.9,14.1,14.6,19,19.9,21.8,25.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,105,11,14.2,14.8,19.2,20.1,22,25.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,105.5,11.1,14.3,14.9,19.4,20.3,22.2,26.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,106,11.2,14.4,15,19.6,20.5,22.5,26.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,106.5,11.3,14.6,15.2,19.8,20.7,22.7,26.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,107,11.4,14.7,15.3,20,20.9,22.9,27),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,107.5,11.5,14.8,15.5,20.2,21.1,23.2,27.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,108,11.6,15,15.6,20.4,21.3,23.4,27.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,108.5,11.7,15.1,15.7,20.6,21.5,23.7,27.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,109,11.7,15.2,15.9,20.8,21.8,23.9,28.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,109.5,11.8,15.4,16,21,22,24.2,28.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,110,11.9,15.5,16.2,21.2,22.2,24.4,28.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,110.5,12,15.7,16.3,21.4,22.4,24.7,29.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,111,12.1,15.8,16.5,21.6,22.7,25,29.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,111.5,12.2,15.9,16.6,21.9,22.9,25.2,29.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,112,12.3,16.1,16.8,22.1,23.1,25.5,30.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,112.5,12.4,16.2,16.9,22.3,23.4,25.8,30.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,113,12.5,16.4,17.1,22.5,23.6,26,30.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,113.5,12.6,16.5,17.3,22.8,23.9,26.3,31.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,114,12.7,16.7,17.4,23,24.1,26.6,31.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,114.5,12.8,16.8,17.6,23.2,24.4,26.9,31.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,115,12.9,17,17.7,23.5,24.6,27.2,32.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,115.5,13,17.1,17.9,23.7,24.9,27.5,32.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,116,13.1,17.3,18.1,23.9,25.1,27.8,33),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,116.5,13.2,17.4,18.2,24.2,25.4,28,33.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,117,13.4,17.6,18.4,24.4,25.6,28.3,33.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,117.5,13.5,17.8,18.6,24.6,25.9,28.6,34.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,118,13.6,17.9,18.7,24.9,26.1,28.9,34.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,118.5,13.7,18.1,18.9,25.1,26.4,29.2,34.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,119,13.8,18.2,19,25.4,26.6,29.5,35.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,119.5,13.9,18.4,19.2,25.6,26.9,29.8,35.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,1,120,14,18.5,19.4,25.8,27.2,30.1,36),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,65,4.6,6,6.2,8.3,8.7,9.7,11.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,65.5,4.7,6.1,6.3,8.5,8.9,9.8,11.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,66,4.8,6.2,6.4,8.6,9,10,11.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,66.5,4.8,6.3,6.5,8.7,9.1,10.1,12),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,67,4.9,6.3,6.6,8.8,9.3,10.2,12.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,67.5,5,6.4,6.7,9,9.4,10.4,12.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,68,5,6.5,6.8,9.1,9.5,10.5,12.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,68.5,5.1,6.6,6.9,9.2,9.7,10.7,12.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,69,5.2,6.7,7,9.3,9.8,10.8,12.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,69.5,5.2,6.8,7.1,9.4,9.9,10.9,13),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,70,5.3,6.9,7.2,9.6,10,11.1,13.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,70.5,5.4,7,7.3,9.7,10.1,11.2,13.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,71,5.4,7,7.4,9.8,10.3,11.3,13.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,71.5,5.5,7.1,7.4,9.9,10.4,11.5,13.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,72,5.6,7.2,7.5,10,10.5,11.6,13.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,72.5,5.6,7.3,7.6,10.1,10.6,11.7,13.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,73,5.7,7.4,7.7,10.2,10.7,11.8,14.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,73.5,5.8,7.5,7.8,10.3,10.8,12,14.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,74,5.8,7.5,7.9,10.4,11,12.1,14.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,74.5,5.9,7.6,8,10.6,11.1,12.2,14.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,75,5.9,7.7,8,10.7,11.2,12.3,14.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,75.5,6,7.8,8.1,10.8,11.3,12.5,14.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,76,6.1,7.9,8.2,10.9,11.4,12.6,14.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,76.5,6.1,7.9,8.3,11,11.5,12.7,15.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,77,6.2,8,8.4,11.1,11.6,12.8,15.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,77.5,6.2,8.1,8.4,11.2,11.7,12.9,15.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,78,6.3,8.2,8.5,11.3,11.8,13.1,15.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,78.5,6.4,8.3,8.6,11.4,12,13.2,15.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,79,6.4,8.3,8.7,11.5,12.1,13.3,15.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,79.5,6.5,8.4,8.8,11.6,12.2,13.4,15.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,80,6.6,8.5,8.9,11.7,12.3,13.6,16.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,80.5,6.6,8.6,9,11.9,12.4,13.7,16.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,81,6.7,8.7,9.1,12,12.6,13.9,16.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,81.5,6.8,8.8,9.2,12.1,12.7,14,16.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,82,6.9,8.9,9.3,12.2,12.8,14.1,16.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,82.5,6.9,9,9.4,12.4,13,14.3,17),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,83,7,9.1,9.5,12.5,13.1,14.5,17.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,83.5,7.1,9.2,9.6,12.6,13.3,14.6,17.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,84,7.2,9.3,9.7,12.8,13.4,14.8,17.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,84.5,7.2,9.4,9.8,12.9,13.5,14.9,17.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,85,7.3,9.5,9.9,13.1,13.7,15.1,17.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,85.5,7.4,9.6,10,13.2,13.8,15.3,18.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,86,7.5,9.7,10.1,13.4,14,15.4,18.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,86.5,7.6,9.8,10.2,13.5,14.2,15.6,18.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,87,7.7,9.9,10.3,13.6,14.3,15.8,18.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,87.5,7.7,10,10.5,13.8,14.5,15.9,18.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,88,7.8,10.1,10.6,13.9,14.6,16.1,19.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,88.5,7.9,10.2,10.7,14.1,14.8,16.3,19.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,89,8,10.3,10.8,14.2,14.9,16.4,19.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,89.5,8,10.4,10.9,14.4,15.1,16.6,19.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,90,8.1,10.5,11,14.5,15.2,16.8,19.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,90.5,8.2,10.6,11.1,14.6,15.4,16.9,20.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,91,8.3,10.8,11.2,14.8,15.5,17.1,20.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,91.5,8.4,10.9,11.3,14.9,15.7,17.3,20.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,92,8.4,11,11.4,15.1,15.8,17.4,20.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,92.5,8.5,11.1,11.5,15.2,16,17.6,20.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,93,8.6,11.2,11.6,15.4,16.1,17.8,21.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,93.5,8.7,11.3,11.8,15.5,16.3,17.9,21.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,94,8.7,11.4,11.9,15.7,16.4,18.1,21.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,94.5,8.8,11.5,12,15.8,16.6,18.3,21.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,95,8.9,11.6,12.1,16,16.7,18.5,21.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,95.5,9,11.7,12.2,16.1,16.9,18.6,22.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,96,9.1,11.8,12.3,16.2,17,18.8,22.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,96.5,9.1,11.9,12.4,16.4,17.2,19,22.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,97,9.2,12,12.5,16.6,17.4,19.2,22.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,97.5,9.3,12.1,12.6,16.7,17.5,19.3,23),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,98,9.4,12.2,12.8,16.9,17.7,19.5,23.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,98.5,9.4,12.3,12.9,17,17.9,19.7,23.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,99,9.5,12.4,13,17.2,18,19.9,23.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,99.5,9.6,12.6,13.1,17.3,18.2,20.1,23.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,100,9.7,12.7,13.2,17.5,18.4,20.3,24.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,100.5,9.8,12.8,13.4,17.7,18.6,20.5,24.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,101,9.9,12.9,13.5,17.9,18.7,20.7,24.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,101.5,10,13,13.6,18,18.9,20.9,24.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,102,10,13.2,13.7,18.2,19.1,21.1,25.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,102.5,10.1,13.3,13.9,18.4,19.3,21.4,25.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,103,10.2,13.4,14,18.6,19.5,21.6,25.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,103.5,10.3,13.5,14.1,18.8,19.7,21.8,26),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,104,10.4,13.7,14.3,19,19.9,22,26.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,104.5,10.5,13.8,14.4,19.2,20.1,22.3,26.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,105,10.6,13.9,14.6,19.3,20.3,22.5,26.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,105.5,10.7,14.1,14.7,19.6,20.5,22.7,27.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,106,10.8,14.2,14.9,19.8,20.8,23,27.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,106.5,10.9,14.4,15,20,21,23.2,27.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,107,11,14.5,15.2,20.2,21.2,23.5,28.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,107.5,11.1,14.6,15.3,20.4,21.4,23.7,28.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,108,11.2,14.8,15.5,20.6,21.7,24,28.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,108.5,11.3,14.9,15.6,20.8,21.9,24.3,29),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,109,11.4,15.1,15.8,21.1,22.1,24.5,29.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,109.5,11.5,15.3,15.9,21.3,22.4,24.8,29.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,110,11.7,15.4,16.1,21.5,22.6,25.1,30),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,110.5,11.8,15.6,16.3,21.8,22.9,25.4,30.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,111,11.9,15.7,16.4,22,23.1,25.7,30.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,111.5,12,15.9,16.6,22.2,23.4,26,31.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,112,12.1,16.1,16.8,22.5,23.6,26.2,31.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,112.5,12.2,16.2,17,22.7,23.9,26.5,31.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,113,12.3,16.4,17.1,23,24.2,26.8,32.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,113.5,12.5,16.6,17.3,23.2,24.4,27.1,32.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,114,12.6,16.7,17.5,23.5,24.7,27.4,32.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,114.5,12.7,16.9,17.7,23.7,25,27.8,33.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,115,12.8,17.1,17.9,24,25.2,28.1,33.7),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,115.5,12.9,17.2,18,24.2,25.5,28.4,34.1),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,116,13.1,17.4,18.2,24.5,25.8,28.7,34.5),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,116.5,13.2,17.6,18.4,24.7,26.1,29,34.9),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,117,13.3,17.7,18.6,25,26.3,29.3,35.3),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,117.5,13.4,17.9,18.8,25.3,26.6,29.6,35.6),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,118,13.5,18.1,18.9,25.5,26.9,29.9,36),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,118.5,13.7,18.3,19.1,25.8,27.2,30.3,36.4),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,119,13.8,18.4,19.3,26,27.4,30.6,36.8),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,119.5,13.9,18.6,19.5,26.3,27.7,30.9,37.2),
('DOH-JHCIS-GROWTH-2026.09.12',2,4,2,120,14,18.8,19.7,26.6,28,31.2,37.6),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,85,0,9.9,10.3,13.9,14.7,16.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,86,0,10.1,10.5,14.1,14.9,16.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,87,0,10.3,10.7,14.3,15.1,16.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,88,0,10.5,10.9,14.6,15.4,16.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,89,0,10.8,11.3,15,15.7,17.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,90,0,11,11.5,15.2,15.9,17.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,91,0,11.2,11.7,15.5,16.2,17.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,92,0,11.4,11.9,15.8,16.5,17.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,93,0,11.6,12.1,16,16.8,18.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,94,0,11.9,12.4,16.4,17.2,18.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,95,0,12.1,12.6,16.7,17.5,19.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,96,0,12.3,12.8,17,17.8,19.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,97,0,12.5,13,17.3,18.1,19.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,98,0,12.7,13.2,17.6,18.4,20.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,99,0,13,13.5,17.9,18.7,20.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,100,0,13.2,13.7,18.2,19,20.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,101,0,13.4,13.9,18.4,19.3,21.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,102,0,13.7,14.2,18.7,19.6,21.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,103,0,13.9,14.5,19,19.9,21.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,104,0,14.1,14.7,19.4,20.3,22.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,105,0,14.4,15,19.7,20.6,22.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,106,0,14.5,15.2,20.1,21,22.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,107,0,14.8,15.5,20.5,21.4,23.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,108,0,15,15.7,20.8,21.7,23.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,109,0,15.3,16,21.1,22.1,24.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,110,0,15.6,16.3,21.6,22.7,24.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,111,0,15.9,16.6,22,23.1,25.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,112,0,16.1,16.8,22.3,23.5,25.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,113,0,16.4,17.1,22.8,24,26.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,114,0,16.7,17.4,23.3,24.5,26.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,115,0,17,17.8,23.8,25,27.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,116,0,17.3,18.1,24.2,25.5,28.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,117,0,17.6,18.4,24.8,26.1,28.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,118,0,18,18.8,25.2,26.6,29.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,119,0,18.3,19.1,25.8,27.2,30.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,120,0,18.6,19.4,26.4,27.9,30.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,121,0,18.9,19.7,26.9,28.5,31.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,122,0,19.3,20.1,27.5,29.1,32.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,123,0,19.6,20.4,28,29.7,33,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,124,0,20,20.8,28.7,30.4,33.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,125,0,20.3,21.2,29.3,31,34.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,126,0,20.7,21.6,29.9,31.7,35.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,127,0,21.1,22,30.7,32.6,36.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,128,0,21.4,22.4,31.3,33.3,37.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,129,0,21.8,22.8,32.1,34.1,38.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,130,0,22.1,23.2,32.9,35,39.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,131,0,22.5,23.7,33.7,35.9,40.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,132,0,23,24.2,34.6,36.8,41.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,133,0,23.4,24.6,35.4,37.8,42.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,134,0,23.8,25.1,36.2,38.7,43.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,135,0,24.3,25.6,37.1,39.6,44.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,136,0,24.7,26,37.9,40.5,45.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,137,0,25.2,26.5,38.8,41.4,46.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,138,0,25.6,27,39.6,42.4,47.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,139,0,26.1,27.5,40.4,43.2,48.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,140,0,26.5,28.1,41.2,44.1,49.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,141,0,27,28.6,42,44.9,50.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,142,0,27.5,29.1,42.8,45.7,51.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,143,0,28,29.6,43.5,46.5,52.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,144,0,28.5,30.2,44.3,47.3,53.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,145,0,29.1,30.8,45.2,48.2,54.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,146,0,29.6,31.3,45.9,49,55.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,147,0,30.2,31.9,46.7,49.9,56.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,148,0,30.8,32.5,47.6,50.8,57.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,149,0,31.4,33.2,48.4,51.6,58,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,150,0,32,33.8,49.1,52.4,58.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,151,0,32.7,34.5,49.9,53.2,59.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,152,0,33.2,35.1,50.7,54,60.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,153,0,33.9,35.9,51.5,54.8,61.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,154,0,34.5,36.5,52.3,55.6,62.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,155,0,35.2,37.2,53.1,56.4,62.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,156,0,35.9,38,54,57.2,63.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,157,0,36.6,38.7,54.8,58,64.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,158,0,37.3,39.5,55.6,58.8,65.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,159,0,38,40.2,56.5,59.7,66,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,160,0,38.6,41,57.3,60.4,66.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,161,0,39.4,41.8,58.2,61.2,67.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,162,0,40.1,42.5,59,62,68.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,163,0,40.8,43.3,59.8,62.8,68.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,164,0,41.5,44,60.6,63.6,69.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,165,0,42.2,44.8,61.5,64.4,70.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,166,0,43,45.6,62.3,65.2,71,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,167,0,43.7,46.3,63.1,66,71.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,168,0,44.4,47.1,63.9,66.8,72.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,169,0,45,47.8,64.7,67.6,73.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,170,0,45.7,48.5,65.5,68.3,73.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,171,0,46.4,49.3,66.3,69.1,74.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,172,0,47.1,50,67,69.8,75.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,173,0,47.9,50.8,67.7,70.5,75.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,174,0,48.6,51.5,68.5,71.1,76.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,175,0,49.4,52.3,69.2,71.8,77.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,176,0,50.1,53,69.9,72.5,77.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,177,0,50.9,53.8,70.6,73.2,78.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,178,0,51.7,54.6,71.2,73.8,79.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,179,0,52.5,55.4,71.9,74.5,79.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,1,180,0,53.3,56.1,72.4,75,80.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,85,0,9.7,10.1,13.5,14.2,15.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,86,0,9.9,10.3,13.8,14.5,15.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,87,0,10.1,10.5,14,14.7,16,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,88,0,10.3,10.7,14.3,15,16.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,89,0,10.5,10.9,14.6,15.3,16.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,90,0,10.7,11.2,14.8,15.5,16.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,91,0,10.9,11.4,15.1,15.8,17.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,92,0,11.1,11.6,15.4,16.1,17.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,93,0,11.3,11.8,15.7,16.4,17.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,94,0,11.5,12,16,16.7,18.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,95,0,11.7,12.2,16.2,17,18.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,96,0,12,12.5,16.5,17.3,18.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,97,0,12.2,12.7,16.9,17.7,19.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,98,0,12.4,12.9,17.2,18,19.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,99,0,12.6,13.2,17.6,18.4,20,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,100,0,12.9,13.4,17.9,18.7,20.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,101,0,13.1,13.7,18.2,19.1,20.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,102,0,13.3,13.9,18.5,19.4,21.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,103,0,13.4,14.1,18.9,19.8,21.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,104,0,13.7,14.4,19.2,20.1,22,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,105,0,13.9,14.6,19.6,20.5,22.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,106,0,14.2,14.9,20,20.9,22.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,107,0,14.4,15.1,20.3,21.3,23.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,108,0,14.7,15.4,20.7,21.7,23.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,109,0,14.9,15.6,21.1,22.2,24.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,110,0,15.2,15.9,21.5,22.6,24.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,111,0,15.4,16.2,21.9,23.1,25.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,112,0,15.7,16.5,22.3,23.5,25.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,113,0,16,16.8,22.8,24,26.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,114,0,16.3,17.1,23.2,24.5,27,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,115,0,16.6,17.4,23.7,25,27.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,116,0,16.8,17.6,24.3,25.6,28.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,117,0,17.1,17.9,24.7,26.1,28.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,118,0,17.4,18.3,25.3,26.7,29.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,119,0,17.7,18.6,25.8,27.4,30.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,120,0,18.1,19,26.5,28.1,31.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,121,0,18.4,19.3,27.1,28.7,31.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,122,0,18.7,19.6,27.7,29.4,32.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,123,0,19,19.9,28.4,30.2,33.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,124,0,19.4,20.4,29.1,30.9,34.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,125,0,19.7,20.7,29.8,31.8,35.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,126,0,19.9,21,30.5,32.6,36.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,127,0,20.3,21.5,31.3,33.4,37.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,128,0,20.6,21.8,32,34.2,38.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,129,0,21,22.2,32.8,35.2,39.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,130,0,21.3,22.6,33.7,36.1,40.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,131,0,21.7,23,34.5,37,42,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,132,0,22.1,23.4,35.3,37.9,43.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,133,0,22.5,23.9,36.2,38.8,44.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,134,0,22.9,24.3,37.1,39.9,45.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,135,0,23.2,24.8,38,40.8,46.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,136,0,23.7,25.3,38.9,41.8,47.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,137,0,24.1,25.8,39.8,42.7,48.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,138,0,24.6,26.3,40.6,43.6,49.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,139,0,25.1,26.9,41.6,44.6,50.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,140,0,25.7,27.5,42.4,45.5,51.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,141,0,26.1,28.1,43.4,46.6,52.9,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,142,0,26.7,28.7,44.3,47.5,53.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,143,0,27.3,29.4,45.2,48.4,54.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,144,0,28,30.1,46.1,49.3,55.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,145,0,28.6,30.7,47,50.3,56.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,146,0,29.3,31.5,47.9,51.2,57.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,147,0,30.1,32.3,48.8,52.1,58.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,148,0,30.8,33,49.7,53,59.5,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,149,0,31.4,33.8,50.5,53.8,60.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,150,0,32.2,34.6,51.4,54.7,61.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,151,0,33,35.4,52.2,55.5,62,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,152,0,33.7,36.1,53,56.3,62.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,153,0,34.5,36.9,53.8,57.1,63.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,154,0,35.2,37.6,54.6,57.9,64.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,155,0,35.9,38.3,55.4,58.7,65.2,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,156,0,36.6,39.1,56.2,59.4,65.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,157,0,37.3,39.8,56.9,60.1,66.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,158,0,38,40.5,57.6,60.8,67.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,159,0,38.7,41.2,58.3,61.4,67.7,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,160,0,39.4,41.9,59,62.1,68.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,161,0,40,42.6,59.7,62.7,68.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,162,0,40.7,43.3,60.3,63.3,69.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,163,0,41.4,44.1,61.1,64,69.8,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,164,0,42,44.8,61.7,64.6,70.3,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,165,0,42.7,45.5,62.3,65.1,70.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,166,0,43.5,46.3,63,65.6,71,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,167,0,44.2,47.1,63.6,66.2,71.4,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,168,0,45,47.9,64.2,66.7,71.6,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,169,0,45.8,48.7,64.9,67.3,72.1,350),
('DOH-JHCIS-GROWTH-2026.09.12',5,18,2,170,0,46.7,49.7,65.5,67.7,72.3,350);

create table if not exists public.growth_reference_versions_v204 (
  reference_version text primary key,
  agency text not null,
  age_0_5_basis text not null,
  age_6_19_basis text not null,
  source_urls jsonb not null default '[]'::jsonb,
  snapshot_sha256 text not null,
  age_reference_rows integer not null,
  wh_reference_rows integer not null,
  active boolean not null default true,
  imported_at timestamptz not null default now()
);

alter table public.growth_reference_versions_v204 enable row level security;

revoke all on public.growth_reference_versions_v204 from public,anon,authenticated;

grant select on public.growth_reference_versions_v204 to authenticated;

drop policy if exists growth_reference_versions_select_v204 on public.growth_reference_versions_v204;

create policy growth_reference_versions_select_v204 on public.growth_reference_versions_v204
for select to authenticated using(active=true);

update public.growth_reference_versions_v204 set active=false where reference_version<>'DOH-JHCIS-GROWTH-2026.09.12';

insert into public.growth_reference_versions_v204
(reference_version,agency,age_0_5_basis,age_6_19_basis,source_urls,snapshot_sha256,age_reference_rows,wh_reference_rows,active)
values(
  'DOH-JHCIS-GROWTH-2026.09.12',
  'เธชเธณเธเธฑเธเนเธ เธเธเธฒเธเธฒเธฃ เธเธฃเธกเธญเธเธฒเธกเธฑเธข เธเธฃเธฐเธ—เธฃเธงเธเธชเธฒเธเธฒเธฃเธ“เธชเธธเธ',
  'เน€เธเธ“เธ‘เนเน€เธเนเธฒเธฃเธฐเธงเธฑเธเธเธฒเธฃเน€เธเธฃเธดเธเน€เธ•เธดเธเนเธ•เน€เธ”เนเธ 0-5 เธเธตเธ—เธตเนเนเธเนเนเธ JHCIS/HDC (เธญเธดเธเธกเธฒเธ•เธฃเธเธฒเธ WHO 2006 เนเธฅเธฐเธเธธเธ”เธเธเธดเธเธฑเธ•เธดเธเธฒเธฃเธเธฃเธกเธญเธเธฒเธกเธฑเธข)',
  'เน€เธเธ“เธ‘เนเธญเนเธฒเธเธญเธดเธเธเธฒเธฃเน€เธเธฃเธดเธเน€เธ•เธดเธเนเธ•เน€เธ”เนเธเธญเธฒเธขเธธ 6-19 เธเธต เธเธฃเธกเธญเธเธฒเธกเธฑเธข เธ.เธจ. 2564',
  '["https://multimedia.anamai.moph.go.th/associates/guide-using-the-growth-criteria-for-children-ages6_19","https://nutrition2.anamai.moph.go.th/th/kidgraph","https://nutrition2.anamai.moph.go.th/th/book/download/?did=226280&id=137253&reload="]'::jsonb,
  '8caf2f7f3fd7ee2e2c4bae157f62d759fe71368eace8d32a760db864709187ba', 868, 666, true
)
on conflict(reference_version) do update set
  agency=excluded.agency,age_0_5_basis=excluded.age_0_5_basis,age_6_19_basis=excluded.age_6_19_basis,
  source_urls=excluded.source_urls,snapshot_sha256=excluded.snapshot_sha256,
  age_reference_rows=excluded.age_reference_rows,wh_reference_rows=excluded.wh_reference_rows,active=true,imported_at=now();

alter table public.health_growth_screenings
  add column if not exists nutrition_result jsonb not null default '{}'::jsonb;

create or replace function private.growth_interpret_v204(
  p_age_months integer,p_gender text,p_weight_kg numeric,p_height_cm numeric
) returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare
  v_ref constant text:='DOH-JHCIS-GROWTH-2026.09.12';
  v_sex smallint;
  v_age_years integer;
  v_weight numeric:=round(p_weight_kg,1);
  v_height numeric:=round(p_height_cm,1);
  wa private.growth_age_reference_v204%rowtype;
  ha private.growth_age_reference_v204%rowtype;
  wh private.growth_wh_reference_v204%rowtype;
  v_wa integer; v_ha integer; v_wh integer;
  v_wa_label text; v_ha_label text; v_wh_label text;
  v_overall_code text; v_overall_label text;
  v_height_gap numeric;
begin
  v_sex:=case lower(btrim(coalesce(p_gender,'')))
    when 'เธเธฒเธข' then 1 when 'm' then 1 when 'male' then 1 when '1' then 1
    when 'เธซเธเธดเธ' then 2 when 'f' then 2 when 'female' then 2 when '2' then 2 else null end;
  if p_age_months is null or p_age_months<0 or p_age_months>227 or v_sex is null or p_weight_kg is null or p_height_cm is null then
    return jsonb_build_object('reference_version',v_ref,'overall_code','reference_unavailable','overall_label','เนเธกเนเธชเธฒเธกเธฒเธฃเธ–เนเธเธฅเธเธฅเธ”เนเธงเธขเน€เธเธ“เธ‘เนเธญเนเธฒเธเธญเธดเธ','reason','เธเนเธญเธกเธนเธฅเธญเธฒเธขเธธ เน€เธเธจ เธเนเธณเธซเธเธฑเธ เธซเธฃเธทเธญเธชเนเธงเธเธชเธนเธเนเธกเนเธเธฃเธ');
  end if;
  v_age_years:=floor(p_age_months/12.0)::integer;

  select * into ha from private.growth_age_reference_v204 r
  where r.reference_version=v_ref and r.age_months=p_age_months and r.sex=v_sex and r.metric='height_for_age';
  if found and v_height between ha.min_value and ha.max_value then
    v_ha:=case when v_height<=ha.level1_high then 1 when v_height<=ha.level2_high then 2 when v_height<=ha.level3_high then 3 when v_height<=ha.level4_high then 4 else 5 end;
    v_ha_label:=case v_ha when 1 then 'เน€เธ•เธตเนเธข' when 2 then 'เธเนเธญเธเธเนเธฒเธเน€เธ•เธตเนเธข' when 3 then 'เธชเนเธงเธเธชเธนเธเธ•เธฒเธกเน€เธเธ“เธ‘เน' when 4 then 'เธเนเธญเธเธเนเธฒเธเธชเธนเธ' when 5 then 'เธชเธนเธ' end;
  end if;

  if p_age_months<72 then
    select * into wa from private.growth_age_reference_v204 r
    where r.reference_version=v_ref and r.age_months=p_age_months and r.sex=v_sex and r.metric='weight_for_age';
    if found and v_weight between wa.min_value and wa.max_value then
      v_wa:=case when v_weight<=wa.level1_high then 1 when v_weight<=wa.level2_high then 2 when v_weight<=wa.level3_high then 3 when v_weight<=wa.level4_high then 4 else 5 end;
      v_wa_label:=case v_wa when 1 then 'เธเนเธณเธซเธเธฑเธเธเนเธญเธขเธเธงเนเธฒเน€เธเธ“เธ‘เน' when 2 then 'เธเนเธณเธซเธเธฑเธเธเนเธญเธเธเนเธฒเธเธเนเธญเธข' when 3 then 'เธเนเธณเธซเธเธฑเธเธ•เธฒเธกเน€เธเธ“เธ‘เน' when 4 then 'เธเนเธณเธซเธเธฑเธเธเนเธญเธเธเนเธฒเธเธกเธฒเธ' when 5 then 'เธเนเธณเธซเธเธฑเธเธกเธฒเธเน€เธเธดเธเน€เธเธ“เธ‘เน' end;
    end if;
  end if;

  select * into wh from private.growth_wh_reference_v204 r
  where r.reference_version=v_ref and r.sex=v_sex and v_age_years between r.age_low_years and r.age_max_years
  order by abs(r.height_cm-v_height),r.height_cm limit 1;
  if found then
    v_height_gap:=abs(wh.height_cm-v_height);
    if v_height_gap<=0.51 and v_weight between wh.min_weight and wh.max_weight then
      v_wh:=case when v_weight<=wh.level1_high then 1 when v_weight<=wh.level2_high then 2 when v_weight<=wh.level3_high then 3 when v_weight<=wh.level4_high then 4 when v_weight<=wh.level5_high then 5 else 6 end;
      v_wh_label:=case v_wh when 1 then 'เธเธญเธก' when 2 then 'เธเนเธญเธเธเนเธฒเธเธเธญเธก' when 3 then 'เธชเธกเธชเนเธงเธ' when 4 then 'เธ—เนเธงเธก' when 5 then 'เน€เธฃเธดเนเธกเธญเนเธงเธ' when 6 then 'เธญเนเธงเธ' end;
    end if;
  end if;

  if v_ha is null or v_wh is null or (p_age_months<72 and v_wa is null) then
    v_overall_code:='reference_unavailable';v_overall_label:='เธกเธตเธเนเธฒเธเธฑเธเธ—เธถเธเนเธฅเนเธง เนเธ•เนเธเธฒเธเธ•เธฑเธงเธเธตเนเธงเธฑเธ”เธญเธขเธนเนเธเธญเธเธเนเธงเธเธเธฃเธฒเธเธญเนเธฒเธเธญเธดเธ';
  elsif v_ha=1 or v_wh in (1,5,6) or (p_age_months<72 and v_wa=1) then
    v_overall_code:='needs_followup';v_overall_label:='เธเธงเธฃเธ•เธดเธ”เธ•เธฒเธกเธ เธฒเธงเธฐเนเธ เธเธเธฒเธเธฒเธฃ';
  elsif v_ha>=3 and v_wh=3 then
    v_overall_code:='good_growth';v_overall_label:='เธชเธนเธเธ”เธตเธชเธกเธชเนเธงเธ';
  else
    v_overall_code:='monitor';v_overall_label:='เธเธงเธฃเน€เธเนเธฒเธฃเธฐเธงเธฑเธเนเธเธงเนเธเนเธกเธเธฒเธฃเน€เธเธฃเธดเธเน€เธ•เธดเธเนเธ•';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'reference_version',v_ref,'reference_agency','เธเธฃเธกเธญเธเธฒเธกเธฑเธข','age_months',p_age_months,
    'policy_group',case when p_age_months<72 then '0-5' else '6-19' end,
    'overall_code',v_overall_code,'overall_label',v_overall_label,
    'weight_for_age',case when p_age_months<72 and v_wa is not null then jsonb_build_object('level',v_wa,'label',v_wa_label,'value',v_weight) else null end,
    'height_for_age',case when v_ha is not null then jsonb_build_object('level',v_ha,'label',v_ha_label,'value',v_height) else null end,
    'weight_for_height',case when v_wh is not null then jsonb_build_object('level',v_wh,'label',v_wh_label,'weight',v_weight,'height',v_height,'reference_height_cm',wh.height_cm) else null end,
    'high_good_proportionate',coalesce(v_ha>=3 and v_wh=3,false)
  ));
end;
$$;

revoke all on function private.growth_interpret_v204(integer,text,numeric,numeric) from public,anon,authenticated;

create or replace function public.save_growth_screening_v190(p_session_id uuid,p_weight_kg numeric,p_height_cm numeric)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  s public.screening_sessions%rowtype;
  p public.health_persons%rowtype;
  v_id uuid; v_nutrition jsonb; v_code text; v_label text; v_ref text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route not in ('child_0_5','school_6_14') then raise exception 'GROWTH_NOT_APPLICABLE'; end if;
  if p_weight_kg is null or p_weight_kg<0.1 or p_weight_kg>300 then raise exception 'INVALID_WEIGHT'; end if;
  if p_height_cm is null or p_height_cm<30 or p_height_cm>250 then raise exception 'INVALID_HEIGHT'; end if;
  select * into p from public.health_persons where source_pcucode=s.source_pcucode and source_pid=s.source_pid;
  if not found then raise exception 'PERSON_NOT_FOUND'; end if;
  v_nutrition:=private.growth_interpret_v204(s.age_months,p.gender,p_weight_kg,p_height_cm);
  v_code:=coalesce(v_nutrition->>'overall_code','reference_unavailable');
  v_label:=coalesce(v_nutrition->>'overall_label','เนเธกเนเธชเธฒเธกเธฒเธฃเธ–เนเธเธฅเธเธฅเธ”เนเธงเธขเน€เธเธ“เธ‘เนเธญเนเธฒเธเธญเธดเธ');
  v_ref:=coalesce(v_nutrition->>'reference_version','DOH-JHCIS-GROWTH-2026.09.12');
  insert into public.health_growth_screenings(session_id,source_pcucode,source_pid,age_months,weight_kg,height_cm,interpretation_code,interpretation_label,reference_version,nutrition_result,screened_by)
  values(s.id,s.source_pcucode,s.source_pid,s.age_months,p_weight_kg,p_height_cm,v_code,v_label,v_ref,v_nutrition,auth.uid()) returning id into v_id;
  update public.screening_sessions set updated_at=now() where id=s.id;
  return jsonb_build_object('ok',true,'id',v_id,'status','interpreted','interpretation',v_label,'interpretation_code',v_code,'reference_version',v_ref,'nutrition',v_nutrition);
end;
$$;

revoke all on function public.save_growth_screening_v190(uuid,numeric,numeric) from public,anon;

grant execute on function public.save_growth_screening_v190(uuid,numeric,numeric) to authenticated;

create or replace function public.growth_timeline_v204(p_source_pcucode text,p_source_pid bigint)
returns table(id uuid,screened_at timestamptz,age_months integer,weight_kg numeric,height_cm numeric,interpretation_code text,interpretation_label text,reference_version text,nutrition_result jsonb)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null or not private.health_can_access_person(p_source_pcucode,p_source_pid) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;
  return query select g.id,g.screened_at,g.age_months,g.weight_kg,g.height_cm,g.interpretation_code,g.interpretation_label,g.reference_version,g.nutrition_result
  from public.health_growth_screenings g where g.source_pcucode=p_source_pcucode and g.source_pid=p_source_pid order by g.screened_at desc limit 50;
end;
$$;

revoke all on function public.growth_timeline_v204(text,bigint) from public,anon;

grant execute on function public.growth_timeline_v204(text,bigint) to authenticated;

create or replace view public.field_export_growth_v200
with (security_invoker=true)
as
select g.id,g.screened_at,g.source_pcucode,g.source_pid,p.display_name,
       h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
       g.age_months,g.weight_kg,g.height_cm,g.interpretation_code,g.reference_version,
       g.interpretation_label,g.nutrition_result
from public.health_growth_screenings g
join public.health_persons p on p.source_pcucode=g.source_pcucode and p.source_pid=g.source_pid
join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode;

grant select on public.field_export_growth_v200 to authenticated;

insert into public.app_settings(key,value)
values('growth_nutrition_reference_v204',jsonb_build_object(
  'version','2.0.4','reference_version','DOH-JHCIS-GROWTH-2026.09.12','agency','เธเธฃเธกเธญเธเธฒเธกเธฑเธข',
  'age_0_5_metrics',jsonb_build_array('weight_for_age','height_for_age','weight_for_height'),
  'age_6_14_metrics',jsonb_build_array('height_for_age','weight_for_height'),
  'bmi_for_age_enabled',false,'snapshot_sha256','8caf2f7f3fd7ee2e2c4bae157f62d759fe71368eace8d32a760db864709187ba',
  'note','6-14 uses the current DOH 6-19 B.E.2564 H/A and W/H reference; historical results retain their reference_version'
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
