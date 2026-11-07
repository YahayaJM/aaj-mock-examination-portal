create extension if not exists pgcrypto;

create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 role text not null default 'admin' check(role in ('admin'))
);

create table if not exists public.students(
 id uuid primary key default gen_random_uuid(),
 exam_year integer not null default 2026,
 exam_number text not null unique,
 surname text not null,
 first_name text not null,
 other_name text default '',
 date_of_birth date not null,
 gender text not null check(gender in ('Male','Female')),
 class_name text not null,
 pin_hash text not null,
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);

create table if not exists public.subjects(
 id uuid primary key default gen_random_uuid(),
 exam_year integer not null,
 name text not null,
 question_count integer not null,
 sort_order integer not null,
 unique(exam_year,name)
);

create table if not exists public.questions(
 id uuid primary key default gen_random_uuid(),
 subject_id uuid not null references public.subjects(id) on delete cascade,
 question_text text not null,
 option_a text not null,
 option_b text not null,
 option_c text not null,
 option_d text not null,
 correct_answer text not null check(correct_answer in ('A','B','C','D')),
 sort_order integer not null,
 created_at timestamptz not null default now()
);
create index if not exists questions_subject_sort on public.questions(subject_id,sort_order);

create table if not exists public.student_answers(
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete cascade,
 question_id uuid not null references public.questions(id) on delete cascade,
 selected_option text not null check(selected_option in ('A','B','C','D')),
 updated_at timestamptz not null default now(),
 unique(student_id,question_id)
);

create table if not exists public.student_subject_attempts(
 student_id uuid not null references public.students(id) on delete cascade,
 subject_id uuid not null references public.subjects(id) on delete cascade,
 answered_count integer not null default 0,
 score integer,
 status text not null default 'in_progress' check(status in ('in_progress','submitted')),
 submitted_at timestamptz,
 primary key(student_id,subject_id)
);

create table if not exists public.student_results(
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete cascade,
 exam_year integer not null,
 exam_number text not null,
 student_name text not null,
 class_name text not null,
 subject_id uuid references public.subjects(id),
 subject_name text not null,
 score integer not null,
 total_questions integer not null,
 percentage numeric(5,2) not null,
 qualification_status text not null check(qualification_status in ('QUALIFIED','NOT QUALIFIED')),
 created_at timestamptz not null default now(),
 unique(student_id,subject_id)
);

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.subjects enable row level security;
alter table public.questions enable row level security;
alter table public.student_answers enable row level security;
alter table public.student_subject_attempts enable row level security;
alter table public.student_results enable row level security;

-- No public table policies are created. The app uses server-only service-role operations.
-- Never put SUPABASE_SERVICE_ROLE_KEY in NEXT_PUBLIC_* variables.

insert into public.subjects(exam_year,name,question_count,sort_order)
select 2026,name,question_count,sort_order from (values
('General Mathematics',50,1),('English Language',50,2),('Physics',50,3),('Chemistry',50,4),('Biology',50,5),
('Geography',17,6),('Computer Studies',17,7),('Hausa Language',17,8),('Literature in English',17,9),
('Agricultural Science',17,10),('Livestock Farming',17,11),('Beauty and Cosmetology',16,12),('Islamic Studies',16,13),('Further Mathematics',16,14)
) as x(name,question_count,sort_order)
on conflict(exam_year,name) do update set question_count=excluded.question_count,sort_order=excluded.sort_order;

create or replace function public.student_login_check(p_exam_number text,p_pin text,p_exam_year integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.students%rowtype;
begin
 select * into s from public.students
 where exam_number=upper(trim(p_exam_number)) and exam_year=p_exam_year and is_active=true;
 if not found or s.pin_hash <> crypt(p_pin,s.pin_hash) then return null; end if;
 return jsonb_build_object('id',s.id,'exam_number',s.exam_number,'exam_year',s.exam_year);
end; $$;

create or replace function public.admin_create_student(
 p_surname text,p_first_name text,p_other_name text,p_dob date,p_gender text,p_class_name text,p_exam_year integer,p_pin text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare n bigint; exam_no text; new_id uuid;
begin
 if auth.role() <> 'service_role' and (auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin')) then raise exception 'Administrator access required'; end if;
 perform pg_advisory_xact_lock(p_exam_year);
 select coalesce(max(substring(exam_number from 12)::bigint),0)+1 into n from public.students where exam_year=p_exam_year;
 exam_no := 'MOCK/'||p_exam_year::text||'/'||lpad(n::text,4,'0');
 insert into public.students(exam_year,exam_number,surname,first_name,other_name,date_of_birth,gender,class_name,pin_hash)
 values(p_exam_year,exam_no,p_surname,p_first_name,coalesce(p_other_name,''),p_dob,p_gender,p_class_name,crypt(p_pin,gen_salt('bf')))
 returning id into new_id;
 return jsonb_build_object('id',new_id,'exam_number',exam_no);
end; $$;

create or replace function public.admin_upsert_question(
 p_exam_year integer,p_subject_name text,p_question_text text,p_a text,p_b text,p_c text,p_d text,p_correct_answer text
) returns void language plpgsql security definer set search_path=public as $$
declare sid uuid; next_order integer;
begin
 if auth.role() <> 'service_role' and (auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin')) then raise exception 'Administrator access required'; end if;
 if upper(p_correct_answer) not in ('A','B','C','D') then raise exception 'Correct answer must be A, B, C or D'; end if;
 select id into sid from public.subjects where exam_year=p_exam_year and name=trim(p_subject_name);
 if sid is null then raise exception 'Unknown subject: %',p_subject_name; end if;
 select coalesce(max(sort_order),0)+1 into next_order from public.questions where subject_id=sid;
 insert into public.questions(subject_id,question_text,option_a,option_b,option_c,option_d,correct_answer,sort_order)
 values(sid,p_question_text,p_a,p_b,p_c,p_d,upper(p_correct_answer),next_order);
end; $$;

create or replace function public.save_student_answer(p_student_id uuid,p_question_id uuid,p_selected_option text)
returns void language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 if upper(p_selected_option) not in ('A','B','C','D') then raise exception 'Invalid option'; end if;
 select subject_id into sid from public.questions where id=p_question_id;
 if sid is null then raise exception 'Question not found'; end if;
 if not exists(select 1 from public.student_subject_attempts where student_id=p_student_id and subject_id=sid and status='in_progress') then
   if exists(select 1 from public.student_subject_attempts where student_id=p_student_id and subject_id=sid and status='submitted') then raise exception 'Subject already submitted'; end if;
   insert into public.student_subject_attempts(student_id,subject_id) values(p_student_id,sid) on conflict do nothing;
 end if;
 insert into public.student_answers(student_id,question_id,selected_option)
 values(p_student_id,p_question_id,upper(p_selected_option))
 on conflict(student_id,question_id) do update set selected_option=excluded.selected_option,updated_at=now();
 update public.student_subject_attempts a set answered_count=(select count(*) from public.student_answers sa join public.questions q on q.id=sa.question_id where sa.student_id=p_student_id and q.subject_id=sid)
 where a.student_id=p_student_id and a.subject_id=sid;
end; $$;

create or replace function public.submit_student_subject(p_student_id uuid,p_subject_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare s public.students%rowtype; sub public.subjects%rowtype; sc integer; total integer; nm text;
begin
 select * into s from public.students where id=p_student_id and is_active=true;
 if not found then raise exception 'Student not found'; end if;
 select * into sub from public.subjects where id=p_subject_id and exam_year=s.exam_year;
 if not found then raise exception 'Subject not found'; end if;
 if exists(select 1 from public.student_subject_attempts where student_id=p_student_id and subject_id=p_subject_id and status='submitted') then raise exception 'Already submitted'; end if;
 select count(*),count(*) filter(where sa.selected_option=q.correct_answer) into total,sc
 from public.questions q left join public.student_answers sa on sa.question_id=q.id and sa.student_id=p_student_id where q.subject_id=p_subject_id;
 if total=0 then raise exception 'No questions have been uploaded for this subject'; end if;
 insert into public.student_subject_attempts(student_id,subject_id,answered_count,score,status,submitted_at)
 values(p_student_id,p_subject_id,(select count(*) from public.student_answers sa join public.questions q on q.id=sa.question_id where sa.student_id=p_student_id and q.subject_id=p_subject_id),sc,'submitted',now())
 on conflict(student_id,subject_id) do update set score=sc,status='submitted',submitted_at=now();
 nm:=concat_ws(' ',s.surname,s.first_name,s.other_name);
 insert into public.student_results(student_id,exam_year,exam_number,student_name,class_name,subject_id,subject_name,score,total_questions,percentage,qualification_status)
 values(s.id,s.exam_year,s.exam_number,nm,s.class_name,sub.id,sub.name,sc,total,round(sc::numeric*100/total,2),case when sc::numeric/total>=0.60 then 'QUALIFIED' else 'NOT QUALIFIED' end)
 on conflict(student_id,subject_id) do update set score=sc,total_questions=total,percentage=round(sc::numeric*100/total,2),qualification_status=case when sc::numeric/total>=0.60 then 'QUALIFIED' else 'NOT QUALIFIED' end;
end; $$;

grant execute on function public.student_login_check(text,text,integer) to service_role;
grant execute on function public.admin_create_student(text,text,text,date,text,text,integer,text) to service_role, authenticated;
grant execute on function public.admin_upsert_question(integer,text,text,text,text,text,text,text) to service_role, authenticated;
grant execute on function public.save_student_answer(uuid,uuid,text) to service_role;
grant execute on function public.submit_student_subject(uuid,uuid) to service_role;


-- One overall row per student. Qualification is based on the combined 400-mark total.
create or replace view public.student_overall_results as
select
 s.id as student_id,
 s.exam_year,
 s.exam_number,
 concat_ws(' ',s.surname,s.first_name,s.other_name) as student_name,
 s.class_name,
 coalesce(sum(r.score),0)::integer as total_score,
 coalesce(sum(r.total_questions),0)::integer as total_questions,
 case when coalesce(sum(r.total_questions),0)=0 then 0
      else round(sum(r.score)::numeric*100/sum(r.total_questions),2) end as percentage,
 case when coalesce(sum(r.total_questions),0)>0 and sum(r.score)::numeric/sum(r.total_questions)>=0.60
      then 'QUALIFIED' else 'NOT QUALIFIED' end as qualification_status,
 jsonb_object_agg(r.subject_name, jsonb_build_object('score',r.score,'out_of',r.total_questions))
   filter(where r.subject_id is not null) as subject_scores
from public.students s
left join public.student_results r on r.student_id=s.id
group by s.id,s.exam_year,s.exam_number,s.surname,s.first_name,s.other_name,s.class_name;
