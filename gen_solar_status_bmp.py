from PIL import Image, ImageDraw, ImageFont
import argparse

import datetime
from datetime import datetime

project_dir='/home/kyle/projects/solar_trmnl'

local_now = str(datetime.now())
# 2020-03-03 09:51:38.570162+01:00
shorter_time = ':'.join(local_now.split(':')[0:2])
# 2020-03-03 09:51


parser = argparse.ArgumentParser()
parser.add_argument("--daily-output", required=True)
parser.add_argument("--total-output", required=True)
args = parser.parse_args()


# Create a monochrome all white image
# trmnl pixel resolution is 800x480 
img = Image.new('1', (800, 480), color='white')

# Initialize ImageDraw
draw = ImageDraw.Draw(img)

# Add logo to the top left
logo = Image.open(project_dir+'/green_team_logo_325.png')  # Your image file here
#logo = logo.resize((100, 100))
#img.paste(logo, (550, 5))
img.paste(logo, (460, 5))

# Draw some text
# Gidole is a OS font from google
font_ttf = project_dir+'/Gidole-Regular.ttf'

# title
title_font = ImageFont.truetype(font_ttf, 60)
hdr_offset_x = 5 
hdr_offset_y = 5
draw.text((hdr_offset_x, hdr_offset_y), "GLC Solar Array", fill='black', font=title_font)
hdr_offset_x += 20
hdr_offset_y += 90

# headers and data
hdr_font = ImageFont.truetype(font_ttf, 50)
data_font = ImageFont.truetype(font_ttf, 40)
#hdr_offset_y = 180

draw.text((hdr_offset_x, hdr_offset_y), "Energy Production:", fill='black', font=hdr_font)
hdr_offset_x += 20
hdr_offset_y += 70
draw.text((hdr_offset_x, hdr_offset_y), "  Yesterday: "+args.daily_output, fill='black', font=data_font)
hdr_offset_y += 60
draw.text((hdr_offset_x, hdr_offset_y), "  Lifetime: "+args.total_output, fill='black', font=data_font)

# ts
ts_font = ImageFont.truetype(font_ttf, 16)
draw.text((600, 450), "Updated: "+shorter_time,  fill='black', font=ts_font)


# Save as BMP
img.save(project_dir+'/output.bmp')
