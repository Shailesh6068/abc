-- Enable Realtime publication and full replica identity for live sync
ALTER TABLE public.race_invitations REPLICA IDENTITY FULL;
ALTER TABLE public.races REPLICA IDENTITY FULL;
ALTER TABLE public.race_participants REPLICA IDENTITY FULL;
ALTER TABLE public.player_presence REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE public.race_invitations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.races;
ALTER PUBLICATION supabase_realtime ADD TABLE public.race_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.player_presence;
