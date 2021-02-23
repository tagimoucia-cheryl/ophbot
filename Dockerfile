FROM python:3.7-slim

COPY requirements.txt ./requirements.txt
RUN pip install -r requirements.txt

COPY main.py ./main.py

# ENTRYPOINT ["python", "main.py"]
# ENTRYPOINT ["bash"]
# ENTRYPOINT ["python"]

