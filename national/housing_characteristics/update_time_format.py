# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
import pandas as pd

df_buildstock = pd.read_csv('buildstock_hvac_nighttime_var_test_60.csv', keep_default_na=False)

list_wkdy_start_time = []
list_wknd_start_time = []
list_wkdy_duration = []
list_wknd_duration = []
for i, row in df_buildstock.iterrows():
    wkdy_start_time = str(row['weekday_start_time'])
    wknd_start_time = str(row['weekend_start_time'])
    wkdy_duration = str(row['weekday_duration'])
    wknd_duration = str(row['weekend_duration'])
    if wkdy_start_time == 'NA':
        list_wkdy_start_time.append(wkdy_start_time)
    else:
        (h, m) = wkdy_start_time.split(':')
        wkdy_start_time = int(h) * 3600 + int(m) * 60
        wkdy_start_time = wkdy_start_time / 3600
        list_wkdy_start_time.append(wkdy_start_time)
    
    if wknd_start_time == 'NA':
        list_wknd_start_time.append(wknd_start_time)
    else:
        (h, m) = wknd_start_time.split(':')
        wknd_start_time = int(h) * 3600 + int(m) * 60
        wknd_start_time = wknd_start_time / 3600
        list_wknd_start_time.append(wknd_start_time)

    if wkdy_duration == 'NA':
        list_wkdy_duration.append(wkdy_duration)
    else:
        (h, m) = wkdy_duration.split(':')
        wkdy_duration = int(h) * 3600 + int(m) * 60
        wkdy_duration = wkdy_duration / 3600
        list_wkdy_duration.append(wkdy_duration)
    
    if wknd_duration == 'NA':
        list_wknd_duration.append(wknd_duration)
    else:
        (h, m) = wknd_duration.split(':')
        wknd_duration = int(h) * 3600 + int(m) * 60
        wknd_duration = wknd_duration / 3600
        list_wknd_duration.append(wknd_duration)

df_buildstock['weekday_start_time'] = list_wkdy_start_time
df_buildstock['weekend_start_time'] = list_wknd_start_time
df_buildstock['weekday_duration'] = list_wkdy_duration
df_buildstock['weekend_duration'] = list_wknd_duration

df_buildstock.to_csv('buildstock_hvac_nighttime_var_test_60.csv', na_rep='NA', index=False)