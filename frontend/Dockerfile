ARG REGISTRY=""
FROM ${REGISTRY}node:20-alpine AS build
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
ARG REACT_APP_API_URL=/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL
RUN npm run build

FROM ${REGISTRY}nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf.template
# Default suits Docker Compose; override BACKEND_URL for other environments
ENV BACKEND_URL=http://backend:8000
EXPOSE 80
CMD ["/bin/sh", "-c", "envsubst '${BACKEND_URL}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
