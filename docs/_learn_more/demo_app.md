---
layout: default
title: Demo App
nav_order: 8
description: "Raif demo application"
---

# Demo App

Raif includes a [demo app](https://github.com/CultivateLabs/raif_demo) that you can use to see the engine in action. Assuming you have Ruby 3.4.2 and Postgres installed, you can run the demo app with:

```bash
git clone git@github.com:CultivateLabs/raif_demo.git
cd raif_demo
bundle install
bin/rails db:create db:prepare
OPENAI_API_KEY=your-openai-api-key-here bin/rails s
```

You can then access the app at [http://localhost:3000](http://localhost:3000).

![Demo App Screenshot](./screenshots/demo-app.png)