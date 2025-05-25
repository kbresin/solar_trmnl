from PIL import Image, ImageDraw, ImageFont
import argparse

import datetime
from datetime import datetime

project_dir='/home/kyle/projects/solar_trmnl'

def get_kwh(s):
  (value, unit) = s.split(' ')
  unit = unit.lower()
  if unit == 'mwh':
    return float(value) * 1000
  if unit == 'gwh':
    return float(value) * 1000000
  if unit in 'kwh':
    return float(value)
  print("Unknown unit, just returning the value")
  return float(value)

local_now = str(datetime.now())
# 2020-03-03 09:51:38.570162+01:00
shorter_time = ':'.join(local_now.split(':')[0:2])
# 2020-03-03 09:51

KWH_TO_CO2_LB=411784.0/265930.0
KWH_TO_DOLLAR=0.075


parser = argparse.ArgumentParser()
parser.add_argument("--daily-output", required=True)
parser.add_argument("--lifetime-output", required=True)
args = parser.parse_args()

lifetime_kwh = get_kwh(args.lifetime_output)
lifetime_co2_lbs = int(lifetime_kwh * KWH_TO_CO2_LB)
lifetime_dollars = int(lifetime_kwh * KWH_TO_DOLLAR)

# Create a monochrome all white image
# trmnl pixel resolution is 800x480 
img = Image.new('1', (800, 480), color='white')

# Initialize ImageDraw
draw = ImageDraw.Draw(img)

# Add logo to the top left
LOGO_FILE = 'green_team_logo_325_sun.png'
logo = Image.open(project_dir+'/'+LOGO_FILE)  # Your image file here
#logo = logo.resize((100, 100))
#img.paste(logo, (550, 5))
img.paste(logo, (470, 5))

# Draw some text
# Gidole is a OS font from google
font_ttf = project_dir+'/Gidole-Regular.ttf'

# initial offset
hdr_offset_x = 10 
hdr_offset_y = 5

# title
title_font = ImageFont.truetype(font_ttf, 60)
draw.text((hdr_offset_x, hdr_offset_y), "GLC Solar Array", fill='black', font=title_font)
hdr_offset_x += 20
hdr_offset_y += 100

# headers and data
hdr_font = ImageFont.truetype(font_ttf, 50)
data_font = ImageFont.truetype(font_ttf, 40)
#hdr_offset_y = 180

# energy production
draw.text((hdr_offset_x, hdr_offset_y), "Energy Production:", fill='black', font=hdr_font)
hdr_offset_x += 20
hdr_offset_y += 55
draw.text((hdr_offset_x, hdr_offset_y), "  Yesterday: "+args.daily_output, fill='black', font=data_font)
hdr_offset_y += 55
draw.text((hdr_offset_x, hdr_offset_y), "  Lifetime: "+args.lifetime_output, fill='black', font=data_font)
hdr_offset_y += 100 

# co2 saved
hdr_offset_x -= 20
draw.text((hdr_offset_x, hdr_offset_y), "Lifetime Savings:", fill='black', font=hdr_font)
hdr_offset_x += 20
hdr_offset_y += 55
draw.text((hdr_offset_x, hdr_offset_y), "  CO2 Reduction: "+'{:,}'.format(lifetime_co2_lbs)+" Pounds", fill='black', font=data_font)
hdr_offset_y += 55
draw.text((hdr_offset_x, hdr_offset_y), "  Energy Savings: $"+'{:,}'.format(lifetime_dollars), fill='black', font=data_font)
hdr_offset_y += 60

# ts
ts_font = ImageFont.truetype(font_ttf, 16)
draw.text((600, 450), "Updated: "+shorter_time,  fill='black', font=ts_font)


# Save as BMP
img.save(project_dir+'/output.bmp')
