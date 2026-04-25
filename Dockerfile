# --- STAGE 1: Build ---
FROM node:20-alpine AS build

# Installation des dépendances système pour Prisma
RUN apk add --no-cache libc6-compat openssl

WORKDIR /app

# Installation des dépendances
COPY package*.json ./
RUN npm ci

# Génération Prisma (besoin du schéma)
COPY prisma ./prisma/
RUN npx prisma generate

# Build TypeScript
COPY . .
RUN npm run build

# Nettoyage des node_modules pour ne garder que la prod
RUN npm prune --production


# --- STAGE 2: Runner ---
FROM node:20-alpine AS runner

# Installation des dépendances système pour Prisma
RUN apk add --no-cache libc6-compat openssl

WORKDIR /app

# Variable d'environnement par défaut
ENV NODE_ENV=production

# On récupère uniquement le nécessaire du stage précédent
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package*.json ./
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/start.sh ./

# Permission d'exécution sur le script
RUN chmod +x start.sh

# Port Fastify (par défaut 3000)
EXPOSE 3000

# Lancement via le script de migration
ENTRYPOINT ["./start.sh"]
