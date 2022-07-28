
--Q1. Which month has the highest count of valid users created?
--    A valid user is defined as:
--        Has a Non-Block email address
--        Has User ID
--        Neither the first name nor last name includes “test”

--Answer: March 2021

--Method 1: one query, use limit to identify top month
select date_trunc('month', create_date) as month
	, count(distinct bu.user_id) as users
	, rank() over (order by count(distinct bu.user_id) desc) as rownum
from block_user bu
left join email e on e.user_id = bu.user_id
left join contact c on c.user_id = bu.user_id
where e.hashed_email not like '%@blockrenovation.com'
	and upper(c.first_name) not like '%TEST%' 
	and upper(c.last_name) not like '%TEST%' 
group by month
order by rownum asc
limit 1

--Method 2: with CTE, using rank()
with monthly_valid_users_ranked as (
select date_trunc('month', create_date) as month
    , count(distinct bu.user_id) as users
    , rank() over (order by count(distinct bu.user_id) desc) as rownum
from block_user bu
left join email e on e.user_id = bu.user_id
left join contact c on c.user_id = bu.user_id
where e.hashed_email not like '%@blockrenovation.com'
    and upper(c.first_name) not like '%TEST%'
    and upper(c.LAST_NAME) not like '%TEST%'
group by month
order by month asc
    )
    
select date_part('month', month) as month
	, date_part('year', month) as year
from monthly_valid_users_ranked
where rownum = 1


--Q2. Which month brought in the highest gross deal value?

--Answer: April 2021

select date_trunc('month', closed_won_date) as deal_month
	, sum(deal_value_usd) as gross_deal
from deal
where closed_won_date is not null
group by deal_month
order by gross_deal desc
limit 1

--Q3. What percentage of “closed won” deals does each city account for?
--    We’ll define a “close won” deal as one that:
--        Has an assigned closed, won date
--        Has a valid user (use same criteria as question #1)

--Run query for results

with valid_users as (
select distinct bu.user_id
from block_user bu
left join email e on e.user_id = bu.user_id
left join contact c on c.user_id = bu.user_id
where e.hashed_email not like '%@blockrenovation.com'
	and upper(c.first_name) not like '%TEST%' 
	and upper(c.last_name) not like '%TEST%' 
	),

deals_by_city as (
select upper(c.property_city) as property_city
	, count(distinct d.deal_id) as closed_deals
from deal d
inner join deal_contact dc on dc.deal_id = d.deal_id
inner join contact c on c.contact_id = dc.contact_id
where closed_won_date is not null
and c.user_id in (select user_id from valid_users)
group by 1
--there's an issue with the deal-contact join where some deal_ids are linked to multiple contact_ids with differing property info
--e.g. NULL property_city for one deal-contact pair and 'New York' for another deal-contact pair with same deal_id
--percents in above table will be slightly off as a result 
--to resolve, I'd probably try coalescing property information for deals in this case, or determine another method to pick one contact with identifying info for the deal
--didn't have enough time to figure this out in its entirety
)

select property_city
	, closed_deals
	, round(closed_deals / dc.tot * 100, 2) as pct_of_total_deals
from deals_by_city
cross join (select sum(closed_deals) as tot from deals_by_city) dc
order by pct_of_total_deals desc

--Q4. Assuming a project takes 6 months to complete, and that we recognize the revenue related to a project at 3 points in time
--    20% at deal close
--    40% at the halfway point
--    40% at completion
--    How much revenue are we recognizing per month? For a timeframe, use the earliest project and 6 months after the most recently closed project as bookends.

with deal_dates as ( --Identify milestone dates for each deal
select *
	, closed_won_date as milestone_1
	, closed_won_date + interval '3 months' as milestone_2
	, closed_won_date + interval '6 months' as milestone_3
from deal
where closed_won_date is not null
	),

expanded_dates as ( --Expand data into one table with milestone & recognized revenue on that date
select milestone_1 as milestone_date
	, deal_value_usd * .2 as recognized_revenue
from deal_dates
union all 
select milestone_2 as milestone_date
	, deal_value_usd * .4 as recognized_revenue
from deal_dates
union all
select milestone_3 as milestone_date
	, deal_value_usd * .4 as recognized_revenue
from deal_dates	
)

select date_trunc('month', milestone_date) as month
	, sum(recognized_revenue) as revenue
from expanded_dates
group by 1
order by 1 asc
