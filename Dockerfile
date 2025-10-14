# Use a lightweight base image with Python 3.10
FROM python:3.10-slim

# Set up a working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*


# Upgrade pip and install Python dependencies
RUN pip install --upgrade pip && \
    pip install numpy scipy nibabel dipy tqdm matplotlib && \
    pip install "git+https://github.com/nrdg/fwe.git"

# Copy your code into the container
COPY . /app

# Copy the runner script and make sure it has Unix line endings, then chmod
COPY containers/babyfwe/run_babyfwe.sh /usr/local/bin/run_babyfwe
RUN sed -i 's/\r$//' /usr/local/bin/run_babyfwe && chmod +x /usr/local/bin/run_babyfwe


# Set the default command to Python (can be overridden later)
CMD ["python3"]
