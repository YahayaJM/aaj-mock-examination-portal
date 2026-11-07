# AAJ MOCK EXAMINATION PORTAL

Independent Next.js + Supabase + Vercel starter for ALFURQAN ACADEMY JAMA’ARE.

## Important status
This is a functional starter foundation, not yet ready for live examinations. Before real students use it, complete the security and workflow checklist below, test with dummy students, and have the school administrator verify the questions and answer key.

## 1. Create Supabase project
Create a new project at Supabase. Open SQL Editor and run `supabase/schema.sql`.

Create an administrator in Supabase Authentication (email/password). Then run:
```sql
insert into public.profiles(id, role)
values ('YOUR_AUTH_USER_UUID', 'admin');
```
Do not expose the service-role key in browser code.

## 2. Configure environment
Copy `.env.example` to `.env.local` and fill in:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-side only)
- `STUDENT_SESSION_SECRET` (32+ random characters)

## 3. Install and run
```bash
npm install
npm run dev
```
Open http://localhost:3000.

## 4. Deploy
Push the project to a new GitHub repository. Import that repository into Vercel. Add the same four environment variables to Vercel Project Settings > Environment Variables, then redeploy.

## 5. Question upload format
Upload CSV/XLSX with exactly these column headings:
`subject, question, A, B, C, D, answer`

The `subject` value must match one of the subjects in `supabase/subjects.csv`. `answer` must be A, B, C or D. This project does not automatically contain the 400 questions; import the reviewed question bank.

## 6. Critical items to finish before live use
- The one-time PIN is displayed once at registration and stored only as a password hash. Implement a controlled PIN reset workflow before production.
- Add bulk student registration and PIN reset.
- Add examination opening/closing windows, per-subject timing, resume rules and final submission controls.
- Add a full per-subject results report and candidate result slip. The overall summary view aggregates submitted subject marks and applies the 60% threshold to the submitted total; until all subjects are submitted, the displayed percentage is provisional.
- Add admin audit logs, rate limiting and failed-login lockout.
- Test simultaneous student submissions, mobile data interruptions and database backups.
- Confirm all 400 questions and correct answers; the generated question bank should be independently reviewed by subject teachers.
- Set the correct academic year and candidate class before production.

## Current starter behaviour
- Student login uses examination number + six-digit PIN.
- Subject and question pages display objective options; answer keys are not selected in student queries.
- Answers are saved through server-side database functions.
- Subject submission calculates a subject result.
- Admin can register a student, upload questions, and export available results.

The SQL functions use `SECURITY DEFINER`; review the SQL and keep the service role key server-only. Enable HTTPS (Vercel provides it).

## Note about exam completeness
This starter currently supports subject-by-subject submissions and calculates an overall percentage from subjects submitted so far. It does not yet enforce a single overall 400-question timed sitting or prevent students from leaving and returning between subjects. Add the school's final timing and examination rules before using it live.
