create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  locale text not null default 'en-US',
  type text not null default 'feature',
  title text not null check (char_length(title) between 1 and 120),
  message text not null check (char_length(message) between 1 and 4000),
  email text,
  app_version text,
  device text,
  status text not null default 'new' check (status in ('new', 'reviewing', 'planned', 'done', 'rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.feedback enable row level security;

drop policy if exists "Anyone can submit feedback" on public.feedback;
create policy "Anyone can submit feedback"
on public.feedback
for insert
to anon
with check (status = 'new');

drop policy if exists "Authenticated admins can read feedback" on public.feedback;
create policy "Authenticated admins can read feedback"
on public.feedback
for select
to authenticated
using (true);

drop policy if exists "Authenticated admins can update feedback" on public.feedback;
create policy "Authenticated admins can update feedback"
on public.feedback
for update
to authenticated
using (true)
with check (true);
