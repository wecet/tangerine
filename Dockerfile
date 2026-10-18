FROM alpine:3.22
RUN apk add --no-cache python3 ffmpeg && addgroup -S tangerine && adduser -S -G tangerine tangerine
WORKDIR /app
COPY --chown=tangerine:tangerine worker/server.py /app/server.py
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
USER tangerine
EXPOSE 8765
CMD ["python3", "/app/server.py"]
