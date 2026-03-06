-- Add team qualification status
-- Run this in the Supabase SQL Editor
-- Default all existing teams to 'qualified'
ALTER TABLE public.teams 
ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'qualified' 
CHECK (status IN ('qualified', 'disqualified'));
