import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'https://wyfgpnjnbzeixwrqtzxe.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind5ZmdwbmpuYnplaXh3cnF0enhlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2NjQ0MjQsImV4cCI6MjA4NzI0MDQyNH0.uJFqbfNTIiW-0r_oYaQxPho8YzaVMDx4phJGB6oLev8';

const supabase = createClient(supabaseUrl, supabaseKey);

async function testSignup() {
    console.log('Sending signup request to Supabase...');
    const startTime = Date.now();

    try {
        const { data, error } = await supabase.auth.signUp({
            email: `debugtest_${Date.now()}@ambiora.in`,
            password: 'Password123!',
            options: {
                data: {
                    display_name: 'Test Setup User',
                    role: 'game_leader'
                }
            }
        });

        console.log(`Response received in ${Date.now() - startTime}ms`);

        if (error) {
            console.error('SUPABASE API ERROR:', error.message);
            console.error(error);
        } else {
            console.log('SIGNUP SUCCESS!');
            console.log('User ID:', data.user.id);

            // Check if profile was created
            const { data: profile, error: profileError } = await supabase
                .from('profiles')
                .select('*')
                .eq('id', data.user.id)
                .single();

            if (profileError) {
                console.error('Trigger failed to create profile!', profileError);
            } else {
                console.log('Profile successfully verified in database:', profile);
            }
        }
    } catch (e) {
        console.error('CRITICAL CRASH:', e);
    }
}

testSignup();
