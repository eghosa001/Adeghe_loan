-- Enforce cross-entity integrity that ordinary foreign keys cannot express.
-- A payment must belong to the same customer as its loan. A document with a
-- loan_id must likewise belong to that loan's customer. This protects the
-- cloud even if a client is modified or local data becomes corrupted.

create or replace function enforce_payment_customer_match()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
    from loans l
    where l.id = new.loan_id
      and l.customer_id = new.customer_id
  ) then
    raise exception 'payment customer does not match loan customer';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_payments_customer_match on payments;
create trigger trg_payments_customer_match
before insert or update of loan_id, customer_id on payments
for each row execute function enforce_payment_customer_match();

create or replace function enforce_document_customer_match()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.loan_id is not null and not exists (
    select 1
    from loans l
    where l.id = new.loan_id
      and l.customer_id = new.customer_id
  ) then
    raise exception 'document customer does not match loan customer';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_documents_customer_match on documents;
create trigger trg_documents_customer_match
before insert or update of loan_id, customer_id on documents
for each row execute function enforce_document_customer_match();
